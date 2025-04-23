# Usage
> kube [-h] [-l] [-s] [-e] [-n \<namespace>|\<pattern>] [cp|pf|pfs|rm] [name] [options]

        -h             show this help and exit
        -l             print the list of containers and exit
        -e             enter inside a container
        -s             shell to execute, used with -e (default is /bin/sh)
        -n <namespace> namespace (default is 'default')
        cp             copy FROM the container
        pf             port forwarding mode (host -> pod)
        pfs            port forwarding mode (host -> service)
        rm             remove a pod 
        name           a full or a partial name of a namespace/service/pod

### cp options:

        path_from      copy from
        path_to        copy to

### port forwarding options:

        [LOCAL_PORT:]REMOTE_PORT - for example '3333:3006' or '3306'

# Examples

> kube -n staging

        use staging namespace;
        the output is the list of pods
        enter pod's index and press Enter to continue

> kube -e bo

        -e - enter inside a container on the 'default' namespace;
        the output is the list of pods which are containing 'bo' in their names
        enter pod's index and press Enter to continue
