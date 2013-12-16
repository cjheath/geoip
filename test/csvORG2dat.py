#!/usr/bin/env python
# Source : https://github.com/mteodoro/mmutils

import sys
import logging
import logging.handlers
import optparse

import csv
import fileinput
import itertools
import struct
import time

from functools import partial

import ipaddr

def init_logger(opts):
    level = logging.INFO
    handler = logging.StreamHandler()
    #handler = logging.handlers.SysLogHandler(address='/dev/log')
    if opts.debug:
        level = logging.DEBUG
        handler = logging.StreamHandler()
    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(handler)

def parse_args(argv):
    if argv is None:
        argv = sys.argv[1:]
    p = optparse.OptionParser()

    cmdlist = []
    for cmd, (f, usage) in sorted(cmds.iteritems()):
        cmdlist.append('%-8s\t%%prog %s' % (cmd, usage))
    cmdlist = '\n  '.join(cmdlist)

    p.usage = '%%prog [options] <cmd> <arg>+\n\nExamples:\n  %s' % cmdlist
    p.add_option('-d', '--debug', action='store_true',
            default=False, help="debug mode")
    p.add_option('-g', '--geoip', action='store_true',
            default=False, help='test with C GeoIP module')
    p.add_option('-w', '--write-dat', help='write filename.dat')
    opts, args = p.parse_args(argv)

    #sanity check
    if not args or args[0] not in cmds:
        p.error('missing command. choose from: %s' % ' '.join(sorted(cmds)))

    return opts, args

def gen_csv(f):
    """peek at rows from a csv and start yielding when we get past the comments
    to a row that starts with an int (split at : to check IPv6)"""
    def startswith_int(row):
        try:
            int(row[0].split(':', 1)[0])
            return True
        except ValueError:
            return False

    cr = csv.reader(f)
    #return itertools.dropwhile(lambda x: not startswith_int(x), cr)
    return cr

class RadixTreeNode(object):
    __slots__ = ['segment', 'lhs', 'rhs']
    def __init__(self, segment):
        self.segment = segment
        self.lhs = None
        self.rhs = None


class RadixTree(object):
    def __init__(self, debug=False):
        self.debug = False

        self.netcount = 0
        self.segments = [RadixTreeNode(0)]
        self.data_offsets = {}
        self.data_segments = []
        self.cur_offset = 1

    def __setitem__(self, net, data):
        self.netcount += 1
        inet = int(net)
        node = self.segments[0]
        for depth in range(self.seek_depth, self.seek_depth - (net.prefixlen-1), -1):
            if inet & (1 << depth):
                if not node.rhs:
                    node.rhs = RadixTreeNode(len(self.segments))
                    self.segments.append(node.rhs)
                node = node.rhs
            else:
                if not node.lhs:
                    node.lhs = RadixTreeNode(len(self.segments))
                    self.segments.append(node.lhs)
                node = node.lhs

        if not data in self.data_offsets:
            self.data_offsets[data] = self.cur_offset
            enc_data = self.encode(*data)
            self.data_segments.append(enc_data)
            self.cur_offset += (len(enc_data))

        if self.debug:
            #store net after data for easier debugging
            data = data, net

        if inet & (1 << self.seek_depth - (net.prefixlen-1)):
            node.rhs = data
        else:
            node.lhs = data

    def gen_nets(self, opts, args):
        raise NotImplementedError

    def load(self, opts, args):
        for nets, data in self.gen_nets(opts, args):
            for net in nets:
                self[net] = data

    def dump_node(self, node):
        if not node:
            #empty leaf
            return '--'
        elif isinstance(node, RadixTreeNode):
            #internal node
            return node.segment
        else:
            #data leaf
            data = node[0] if self.debug else node
            return '%d %s' % (len(self.segments) + self.data_offsets[data], node)

    def dump(self):
        for node in self.segments:
            print node.segment, [self.dump_node(node.lhs), self.dump_node(node.rhs)]

    def encode(self, *args):
        raise NotImplementedError

    def encode_rec(self, rec, reclen):
        """encode rec as 4-byte little-endian int, then truncate it to reclen"""
        assert(reclen <= 4)
        return struct.pack('<I', rec)[:reclen]

    def serialize_node(self, node):
        if not node:
            #empty leaf
            rec = len(self.segments)
        elif isinstance(node, RadixTreeNode):
            #internal node
            rec = node.segment
        else:
            #data leaf
            data = node[0] if self.debug else node
            rec = len(self.segments) + self.data_offsets[data]
        return self.encode_rec(rec, self.reclen)

    def serialize(self, f):
        if len(self.segments) >= 2 ** (8 * self.segreclen):
            logging.warning('too many segments for final segment record size!')

        for node in self.segments:
            f.write(self.serialize_node(node.lhs))
            f.write(self.serialize_node(node.rhs))

        f.write(chr(42)) #So long, and thanks for all the fish!
        f.write(''.join(self.data_segments))

        f.write('bat.bast') #.dat file comment - can be anything
        f.write(chr(0xFF) * 3)
        f.write(chr(self.edition))
        f.write(self.encode_rec(len(self.segments), self.segreclen))

class ORGIPRadixTree(RadixTree):
    usage = '-w mmorg.dat mmorg_ip GeoIPORG.csv'
    cmd = 'mmorg_ip'
    seek_depth = 31
    edition = 5
    reclen = 4
    segreclen = 4

    def gen_nets(self, opts, args):
        for lo, hi, org in gen_csv(fileinput.input(args)):
            lo, hi = ipaddr.IPAddress(lo), ipaddr.IPAddress(hi)
            nets = ipaddr.summarize_address_range(lo, hi)
            #print 'lo %s - li %s - nets %s - org %s' % (lo, hi, nets, org)
            yield nets, (org,)

    def encode(self, data):
        return data + '\0'

class ORGNetworkRadixTree(RadixTree):
    usage = '-w mmorg.dat mmorg_net GeoIPORG.csv'
    cmd = 'mmorg_net'
    seek_depth = 31
    edition = 5
    reclen = 4
    segreclen = 4

    def gen_nets(self, opts, args):
        for net, org in gen_csv(fileinput.input(args)):
            net = [ipaddr.IPNetwork(net)]
            yield net, (org,)

    def encode(self, data):
        return data + '\0'

def build_dat(RTree, opts, args):
    tstart = time.time()
    r = RTree(debug=opts.debug)

    r.load(opts, args)

    if opts.debug:
        r.dump()

    with open(opts.write_dat, 'wb') as f:
        r.serialize(f)

    tstop = time.time()
    print 'wrote %d-node trie with %d networks (%d distinct labels) in %d seconds' % (
            len(r.segments), r.netcount, len(r.data_offsets), tstop - tstart)


rtrees = [ORGIPRadixTree, ORGNetworkRadixTree]
cmds = dict((rtree.cmd, (partial(build_dat, rtree), rtree.usage)) for rtree in rtrees)

def main(argv=None):
    global opts
    opts, args = parse_args(argv)
    init_logger(opts)
    logging.debug(opts)
    logging.debug(args)

    cmd = args.pop(0)
    cmd, usage = cmds[cmd]
    return cmd(opts, args)

if __name__ == '__main__':
    rval = main()
    logging.shutdown()
    sys.exit(rval)
