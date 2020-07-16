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
        provider='process(@BIN_MON)'
        ;;

ceph-mgr)
        stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
        provider='process(@BIN_MGR)'
        ;;

ceph-osd)
        stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
        provider='process(@BIN_OSD)'
        ;;

ceph-mds)
        stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
        provider='process(@BIN_MDS)'
        ;;

ceph-fuse)
        stapopt="--ldd -I $TAPSET_CEPH_PATH $stapopt"
        provider='process(@BIN_FUSE)'
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
        msg = $m;
        peeraddr = msg->connection->px->peer_addr->u->sin->sin_addr->s_addr;
        port = msg->connection->px->peer_addr->u->sin->sin_port;
        type = msg->connection->px->peer_type;
        nonce = msg->connection->px->peer_addr->nonce;

        ansi_set_color(32);
        printf("%18d  %15s/%d  %-30s  %-35s  %-5d  <-- %8s  %-s:%-d/%-d\n",
                gettimeofday_us() - lasttime[pid(), peeraddr, port, type, nonce],
                execname(), pid(), ppfunc(), ceph_msg_getname(msg), msg->header->priority->v,
                ceph_entity_type_name(type),
                format_ipaddr(peeraddr, 2), ntohs(port), nonce);
        ansi_reset_color();

        lasttime[pid(), peeraddr, port, type, nonce] = gettimeofday_us();
}

probe   '$provider'.function("AsyncConnection::write_message")
{
        msg = $m;
        peeraddr = msg->connection->px->peer_addr->u->sin->sin_addr->s_addr;
        port = msg->connection->px->peer_addr->u->sin->sin_port;
        type = msg->connection->px->peer_type;
        nonce = msg->connection->px->peer_addr->nonce;


        ansi_set_color(31);
        printf("%18d  %15s/%d  %-30s  %-35s  %-5d  ==> %8s  %-s:%-d/%-d\n",
                gettimeofday_us() - lasttime[pid(), peeraddr, port, type, nonce],
                execname(), pid(), ppfunc(), ceph_msg_getname(msg), msg->header->priority->v,
                ceph_entity_type_name(type),
                format_ipaddr(peeraddr, 2), ntohs(port), nonce);
        ansi_reset_color();

        lasttime[pid(), peeraddr, port, type, nonce] = gettimeofday_us();
}
' | c++filt
