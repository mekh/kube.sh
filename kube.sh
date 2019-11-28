#!/usr/bin/env bash
# set -x

# ----- Help string -----
script=$(basename "$0");
usage="$script [-h] [-l] [-e] <namespace> [cp] [name] [from] [to]

where:
    -h          show this help and exit
    -e          enter inside a container
    -l          print the list of containers and exit
    <namespace> either -s for staging or -p for the production environment
    cp          copy from the container
    name        a full or a part name of pod
    from        copy from
    to          copy to


Examples

# List all pods
$script -s
    -s - use staging namespace;
    the output is the list of pods
    enter pod's index and press Enter to continue

# Enter inside a pod
$script -p -e bo
   -p - use production namespace;
   -e - enter inside a container;
   the output is the list of pods which are containing 'bo' in their names
   enter pod's index and press Enter to continue

# Copy a directory from inside a pod to local machine
$script -s cp pod-name /path/inside/pod/ /local/path
"
# ----- Check whether the kubectl is installed -----

if ! [[ -x "$(command -v kubectl)" ]]; then
    echo "kubectl is not installed"
    exit 1
fi;

# ----- Get parameters -----

for i in "$@";do
    case $i in
        -s) namespace=staging;;
        -p) namespace=production;;
        -z) namespace=default;;
        -e) exec=true;;
        -l) listAndExit=true;;
        cp) cp=true;;
        -h) echo -e "$usage"; exit;;
        *) pod="${i}"
    esac
done

# ----- Parameters validation -----

if [[ -z $namespace ]]; then
    (>&2 echo -e "Please specify the namespace\n\n$usage")
    exit 1
fi;

if [[ $cp == true ]]; then
    length=$#;
    args=("$@")

    pod=${args[$((length-3))]};
    path_from=${args[$((length-2))]};
    path_to=${args[$((length-1))]};
fi
# ----- Checking if the kubectl is properly configured and getting the list of pods -----

if ! list=$(kubectl -n ${namespace} get pods); then
    exit 1
fi;

header=$(echo "$list" | head -n1);
containers=$(echo "$list" | grep -v NAME | grep "$pod");

if [[ -z $containers ]]; then
    (>&2 echo "No pod with the given name (${pod}) found")
    exit 1
fi;

num=$(echo "$containers" | wc -l)
echo "IDX $header"

if [[ $num == 1 ]]; then
    container=$(echo "$containers" | awk '{print $1}');
fi;

n=1;
arr=();

while read -r line; do
    echo "$(printf "%3d" ${n}) ${line}"
    pod_name=$(echo "$line" | awk '{print $1}')
    arr+=("$pod_name");
    n=$((n+1))
done <<< "$containers"

if [[ ${listAndExit} == true ]]; then
      exit 0
elif [[ $num -gt 1 ]]; then
    index="";
    re='^[0-9]+$'

    validate() {
        local result=0
        if [[ ! "$index" =~ $re || index -lt 1 || index -gt ${#arr[@]} ]]; then
            if [[ "$index" != "" ]]; then
                echo " Invalid index entered. Try again or press CTRL+C to exit"
            fi;
            result=1;
        fi;

        return $result
    }

    while ! validate; do
      echo -ne "Enter a pod index: "
      read -r index
    done;

    container=${arr[$((index-1))]}
fi;

# ----- Executing -----
ARGS=("-n" "$namespace")

if [[ ${exec} == true ]]; then
    ARGS+=("exec" "-it" "$container" "bash")
elif [[ ${cp} == true ]]; then
    ARGS+=("cp" "${container}:${path_from}" "$path_to")
else
    ARGS+=("logs" "-f" "$container")
fi;

# shellcheck disable=SC2068
kubectl ${ARGS[@]}
