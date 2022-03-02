#!/usr/bin/env bash
#
# This script has been heavily edited from its original source
# This was taken from https://raw.githubusercontent.com/cilium/cilium-perf-networking/master/scripts/knb-run.sh

set -e

# dorr_single runs a single test without bursting
# this is used to get some quick feedback when configuring
# different options
function dorr_single() {
    local proto=$1
    $xdir/knb \
        pod2pod \
            --duration 60 \
            --run-label "${proto}_b0" \
            --client-affinity host=$cli_node \
            --server-affinity host=$srv_node \
            --netperf-type $proto \
            --netperf-args "-D" --netperf-args "10" \
            --netperf-bench-args "-r" --netperf-bench-args "1,1" \
            --netperf-bench-args "-b" --netperf-bench-args 0
}

# dorr will run a series of tests for 2 minutes each in bursts 
function dorr() {
    local proto=$1
    for burst in 1 96; do
        $xdir/knb \
            pod2pod \
                --duration 300 \
                --run-label "${proto}_b${burst}" \
                --client-affinity host=$cli_node \
                --server-affinity host=$srv_node \
                --netperf-type $proto \
                --netperf-args "-D" --netperf-args "10" \
                --netperf-bench-args "-r" --netperf-bench-args "1,1" \
                --netperf-bench-args "-b" --netperf-bench-args ${burst}
    done
}

# dorr_host runs a series of tests using host networking
function dorr_host() {
    local proto=$1
    for burst in 1 96; do
        $xdir/knb \
            pod2pod \
                --duration 300 \
                --run-label "${proto}_b${burst}_host" \
                --client-affinity host=$cli_node \
                --server-affinity host=$srv_node \
                --netperf-type $proto \
                --netperf-args "-D" --netperf-args "10" \
                --netperf-bench-args "-r" --netperf-bench-args "1,1" \
                --netperf-bench-args "-b" --netperf-bench-args ${burst} \
                --cli-on-host \
                --srv-on-host
    done
}

# dostream runs a streaming test 
function dostream() {
    local proto=$1
    for nstreams in 1 96; do
        $xdir/knb \
            pod2pod \
                --duration 300 \
                --run-label "${proto}_n${nstreams}" \
                --netperf-nstreams ${nstreams} \
                --client-affinity host=$cli_node \
                --server-affinity host=$srv_node \
                --netperf-type $proto \
                --netperf-args "-D" --netperf-args "10" 
    done
}

# dostream_host runs a streaming test using host networking
function dostream_host() {
    local proto=$1
    for nstreams in 1 96; do
        $xdir/knb \
            pod2pod \
                --duration 300 \
                --run-label "${proto}_n${nstreams}_host" \
                --netperf-nstreams ${nstreams} \
                --client-affinity host=$cli_node \
                --server-affinity host=$srv_node \
                --netperf-type $proto \
                --netperf-args "-D" --netperf-args "10"  \
                --cli-on-host \
                --srv-on-host
    done
}

nloops=1

while true; do
    case $1 in
        --tcp_stream)
            run_tcp_stream=1
            ;;

        --tcp_stream_host)
            run_tcp_stream_host=1
            ;;

        --tcp_rr)
            run_tcp_rr=1
            ;;

        --tcp_rr_single)
            run_tcp_rr_single=1
            ;;

        --tcp_rr_host)
            run_tcp_rr_host=1
            ;;

        --nloops)
            if [ "$2" ]; then
                nloops=$2
                shift
            else
                echo >2 "--nloops requires argument"
                exit 1
            fi
            ;;

        -?*)
              echo 'WARN: Unknown option (ignored): %s' "$1" >&2
              ;;

        --)
            shift
            break
            ;;

        *)
            break
    esac
    shift
done

if [ -z "$1" ]; then
    echo >&2 "Usage: $0 [--{tcp,udp}_stream] [--tcp_maerts] [--{tcp,udp}_rr] [--all] [--nloops n] [--dry-run] <dir>"
    exit 1
fi

xdir=$1
cli_node=$(kubectl get nodes -o json | jq -r '.items[0].metadata.name')
srv_node=$(kubectl get nodes -o json | jq -r '.items[1].metadata.name')

./kubenetbench init -s $xdir --port-forward

for _ in $(seq $nloops) ; do
    # Stream
    if [ "$run_tcp_stream" == "1" ]; then
        dostream "tcp_stream"
    fi
    if [ "$run_tcp_stream_host" == "1" ]; then
        dostream_host "tcp_stream"
    fi

    # RR
    if [ "$run_tcp_rr" == "1" ]; then
        dorr "tcp_rr"
    fi
    if [ "$run_tcp_rr_single" == "1" ]; then 
        dorr_single "tcp_rr"
    fi
    if [ "$run_tcp_rr_host" == "1" ]; then 
        dorr_host "tcp_rr"
    fi
done

kubectl delete ds/knb-monitor

echo "done"