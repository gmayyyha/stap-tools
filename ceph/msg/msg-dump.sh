#!/bin/sh
# -xv

#
# print message names sent or recept by ceph entiry.
#

TAPSET_CEPH_PATH="../../tapset/ceph"

provider=
pid=
stapopt="-v"
entity=
dumpstack=0
dumpmsg=""

usage()
{
        echo "./msg-dump [-p pid] [-s] [-m name] entity"
        echo "ceph entity: ceph-mon, ceph-mgr, ceph-osd, ceph-mds,
                           ceph-fuse, libceph, ceph or rbd" >&2
        exit 1
}

while getopts "m:p:s" opt; do
        case $opt in
        p)
                pid=$OPTARG
                ;;

        s)
                dumpstack=1
                ;;

        m)
                dumpmsg=$OPTARG
                ;;

        *)
                ;;
        esac
done
shift $(($OPTIND - 1))

[ $# -ne 1 ] && usage

entity=$1
case $entity in
ceph-mon)
	stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
	if [ "x$pid" != "x" ]; then
		stapopt="-x $pid $stapopt"
	fi
	provider='process(@BIN_MON).library("libceph-common.so.*")'
	;;

ceph-mgr)
	stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
	if [ "x$pid" != "x" ]; then
		stapopt="-x $pid $stapopt"
	fi
	provider='process(@BIN_MGR).library("libceph-common.so.*")'
	;;

ceph-osd)
	stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
	if [ "x$pid" != "x" ]; then
		stapopt="-x $pid $stapopt"
	fi
	provider='process(@BIN_OSD)'
	;;

ceph-mds)
	stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
	if [ "x$pid" != "x" ]; then
		stapopt="-x $pid $stapopt"
	fi
	provider='process(@BIN_MDS).library("libceph-common.so.*")'
        ;;

ceph-fuse)
	stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
	if [ "x$pid" != "x" ]; then
		stapopt="-x $pid $stapopt"
	fi
	provider='process(@BIN_FUSE).library("libceph-common.so.*")'
	;;

*)
        usage
        ;;
esac

[ "x$provider" != "x" ] && stap $stapopt -e '
global dumpstack = '$dumpstack'

global lasttime;

probe   '$provider'.function("DispatchQueue::enqueue@*/src/msg/DispatchQueue.cc")
,       '$provider'.function("DispatchQueue::fast_dispatch@*/src/msg/DispatchQueue.cc")
{
	msg = $m->px;
	if ("'$dumpmsg'" == "" || ceph_msg_getname(msg) =~ "'$dumpmsg'") {
		if (target() == pid() || "'$pid'" == "") {
			ms_type = msg->header->type->v;
			addr = msg->connection->px->peer_addrs->current;
			peeraddr = addr->v->_M_impl->_M_start->u->sin->sin_addr->s_addr;
			port = addr->v->_M_impl->_M_start->u->sin->sin_port;
			type = msg->connection->px->peer_type;
			nonce = addr->v->_M_impl->_M_start->nonce;

			ansi_set_color(32);
			printf("%18d  %15s/%d  %-30s  %-35s  %-5d  <== %8s  %-s:%-d/%-d\n",
			        gettimeofday_us() - lasttime[pid(), peeraddr, port, type, nonce],
			        execname(), pid(), ppfunc(), ceph_msg_getname(msg), msg->header->priority->v,
			        ceph_entity_type_name(type),
			        format_ipaddr(peeraddr, 2), ntohs(port), nonce);
			ceph_msg_dump(msg);
			ansi_reset_color();

			lasttime[pid(), peeraddr, port, type, nonce] = gettimeofday_us();
		}
	}
}

probe   '$provider'.function("Protocol*::write_message")
{
	msg = $m;
	if ("'$dumpmsg'" == "" || ceph_msg_getname(msg) =~ "'$dumpmsg'") {
		if (target() == pid() || "'$pid'" == "") {
			ms_type = msg->header->type->v;
			addr = msg->connection->px->peer_addrs->current;
			peeraddr = addr->v->_M_impl->_M_start->u->sin->sin_addr->s_addr;
			port = addr->v->_M_impl->_M_start->u->sin->sin_port;
			type = msg->connection->px->peer_type;
			nonce = addr->v->_M_impl->_M_start->nonce;

			ansi_set_color(31);
			printf("%18d  %15s/%d  %-30s  %-35s  %-5d  --> %8s  %-s:%-d/%-d\n",
			        gettimeofday_us() - lasttime[pid(), peeraddr, port, type, nonce],
			        execname(), pid(), ppfunc(), ceph_msg_getname(msg), msg->header->priority->v,
			        ceph_entity_type_name(type),
			        format_ipaddr(peeraddr, 2), ntohs(port), nonce);
			ceph_msg_dump(msg);
			ansi_reset_color();

			lasttime[pid(), peeraddr, port, type, nonce] = gettimeofday_us();
		}
	}
}
' | c++filt
