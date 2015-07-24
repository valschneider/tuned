#!/bin/sh

. /usr/lib/tuned/functions

ltanfile=/sys/module/kvm/parameters/lapic_timer_advance_ns

start() {
    python /usr/libexec/tuned/defirqaffinity.py "remove" "$TUNED_isolated_cores_expanded" &&
    tuna -c "$TUNED_isolated_cores_expanded" -i
    retval = "$?"

    if [ ! $retval -eq 0 ]; then
        return $retval
    fi

    modinfo -p kvm | grep -q kvmclock_periodic_sync
    if [ "$?" -eq 0 ]; then
        echo "options kvm kvmclock_periodic_sync=0" > /etc/modprobe.d/kvm.rt.tuned.conf
    fi

    modinfo -p kvm_intel | grep -q ple_gap
    if [ "$?" -eq 0 ]; then
        echo "options kvm_intel ple_gap=0" >> /etc/modprobe.d/kvm.rt.tuned.conf
    fi

    if [ -f lapic_timer_adv_ns.cpumodel ]; then
        curmodel=`cat /proc/cpuinfo | grep "model name" | cut -f 2 -d ":" | uniq`
        genmodel=`cat lapic_timer_adv_ns.cpumodel`

        if [ "$cpumodel" != "$genmodel" ]; then
            rm -f lapic_timer_adv_ns
            rm -f lapic_timer_adv_ns.cpumodel
        fi
    fi


    if [ -f $ltanfile -a ! -f ./lapic_timer_adv_ns ]; then
        if [ -f /usr/share/qemu-kvm/tscdeadline_latency.flat ]; then
             tempdir=`mktemp -d`
             isolatedcpu=`echo "$TUNED_isolated_cores_expanded" | cut -f 1 -d ","`
             sh ./run-tscdeadline-latency.sh $isolatedcpu > $tempdir/lat.out
             sh ./find-lapictscdeadline-optimal.sh $tempdir/lat.out > $tempdir/opt.out
             if [ $? -eq 0 ]; then
                  echo `cat $tempdir/opt.out | cut -f 2 -d ":"` > ./lapic_timer_adv_ns
                  curmodel=`cat /proc/cpuinfo | grep "model name" | cut -f 2 -d ":" | uniq`
                  echo $curmodel > lapic_timer_adv_ns.cpumodel
             fi
        fi
    fi
    if [ -f $ltanfile -a -f ./lapic_timer_adv_ns ]; then
        echo `cat ./lapic_timer_adv_ns` > $ltanfile
    fi

    return $retval
}

stop() {
    rm -f /etc/modprobe.d/kvm.rt.tuned.conf
    tuna -c "$TUNED_isolated_cores_expanded" -I &&
    python /usr/libexec/tuned/defirqaffinity.py "add" "$TUNED_isolated_cores_expanded"
    return "$?"
}

verify() {
    python /usr/libexec/tuned/defirqaffinity.py "verify" "$TUNED_isolated_cores_expanded"
    retval = "$?"
    if [ $retval -eq 0 -a -f /sys/module/kvm/parameters/kvmclock_periodic_sync ]; then
        retval = `cat /sys/module/kvm/parameters/kvmclock_periodic_sync`
    fi
    if [ $retval -eq 0 -a -f /sys/module/kvm_intel/parameters/ple_gap ]; then
        retval = `cat /sys/module/kvm_intel/parameters/ple_gap`
    fi
    return $retval
}

process $@
