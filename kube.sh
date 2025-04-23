#!/usr/bin/env bash
# set -x

script_name=$(basename "$0")
default_shell="/bin/sh"
default_namespace="default"
default_log_time="15m"
list_type="po"; # po | service
positional_args=();
namespaceBlackList=();

# ----- Help string -----
usage="$script_name [-h] [-l] [-s] [-e] [-n -|<namespace>|<pattern>] [cp|pf|rm] [name] [options]

where:
    -h             show this help and exit
    -e             enter inside a container
    -s             shell to execute, used with -e (default is $default_shell)
    -l             print the list of containers and exit
    -n <namespace> namespace (default is 'default')
    cp             copy FROM the container
    pf             port forwarding mode (host -> pod)
    pfs            port forwarding mode (host -> service)
    rm             remove a pod
    name           a full or a partial name of a namespace/service/pod

cp options:
    path_from      copy from
    path_to        copy to

port forwarding options:
    [LOCAL_PORT:]REMOTE_PORT - for example '3333:3006' or '3306'

Examples

$script_name -n staging
    use staging namespace;
    the output is the list of pods
    enter pod's index and press Enter to continue

$script_name -e bo
   -e - enter inside a container on the '$default_namespace' namespace;
   the output is the list of pods which are containing 'bo' in their names
   enter pod's index and press Enter to continue
"

# ----- Get parameters -----
while [[ $# -gt 0 ]]; do
  case $1 in
  -x)
    context=$2;
    if [[ $context =~ ^-.* || -z $context || $context == 'cp' || $context == 'pf' || $context == 'rm' ]]; then
      context="-";
      shift 1;
    else
      shift 2;
    fi
    ;;
  -n)
    namespace=$2;
    if [[ $namespace =~ ^-.* || -z $namespace || $namespace == 'cp' || $namespace == 'pf' || $namespace == 'rm' ]]; then
      namespace="-";
      shift 1;
    else
      shift 2;
    fi
    ;;
  -e)
    exec=true;
    shift;
    ;;
  -s)
    default_shell=$2;
    shift 2;
    ;;
  -l)
    list_and_exit=true;
    shift;
    ;;
  cp)
    cp=true;
    shift;
    ;;
  pf)
    port_forward=true;
    shift;
    ;;
  pfs)
    port_forward=true;
    list_type="service";
    shift;
    ;;
  rm)
    remove_pod=true;
    shift;
    ;;
  -h)
    echo -e "$usage";
    exit 0;
    ;;
  *)
    positional_args+=("$1");
    shift;
    ;;
  esac
done

read_list_index() {
  local list_index="";
  local re='^[0-9]+$';

  validate_index() {
    if [[ ! $list_index =~ $re || $list_index -lt 1 || $list_index -gt ${#input_array[@]} ]]; then
      if [[ $list_index != "" ]]; then
        echo "Invalid index entered. Try again or press CTRL+C to exit";
      fi
      return 1;
    fi

    return 0;
  }

  list_count=$(echo "$list_items" | wc -l);
  if [[ $list_count -eq 1 ]]; then
    list_idx=0;
    return 0;
  fi;

  while ! validate_index; do
    echo -ne "Enter an index: ";
    read -r list_index;
  done

  list_idx=$((list_index - 1));
  return $list_idx;
}

print_list_items() {
  input_array=();
  local item_index=1;
  [[ -n $list_header ]] && echo "    $list_header";

  while read -r; do
    line="$REPLY";
    echo "$(printf "%3d" ${item_index}) ${line}";
    name=$(echo "$line" | awk '{print $1}');
    input_array+=("$name");
    item_index=$((item_index + 1));
  done <<< "$list_items";
}

get_list_item() {
  list_header=$(echo "$list" | head -n1);
  list_items=$(echo "$list" | grep -v "$list_header" | grep "$name_pattern");

  if [[ -z $list || -z $list_items ]] ; then
    (echo >&2 "No item with the given pattern (${name_pattern}) found");
    exit 1;
  fi

  if [[ -n $1 ]]; then # list filtering
    IFS_BKP="$IFS"
    IFS=$'\n'

    filter=("$@")
    for item in "${filter[@]}"; do
      list_items=$(echo "$list_items" | grep -vE "^${item}[[:space:]].*");
    done

    IFS="$IFS_BKP"
  fi

  list_count=$(echo "$list_items" | wc -l);

  print_list_items;
}

# ----- Check whether the kubectl is installed -----
if ! [[ -x $(command -v kubectl) ]]; then
  echo "kubectl - command not found";
  exit 1;
fi

if [[ -n $context ]]; then
  [[ $context == '-' ]] || name_pattern="$context";

  list=$(kubectl config get-contexts);
  [[ $? == 1 ]] && exit 1;

  get_list_item;
  read_list_index;

  context=${input_array[$list_idx]};

  echo "Using context: $context";

  [[ $context && $context != '*' ]] && kubectl config use-context "$context"

  exit 0;
fi

# ----- Get the namespace -----
[[ $namespace == "-" || -z $namespace ]] || name_pattern="$namespace"; # get all namespaces if namespace='-', grep by pattern otherwise

list=$(kubectl get namespace);
[[ $? == 1 ]] && exit 1;

get_list_item "${namespaceBlackList[@]}";
read_list_index;

namespace=${input_array[$list_idx]};

if [[ -z $namespace ]]; then
  namespace=$default_namespace;
fi

name_pattern=${positional_args[0]};

#<editor-fold desc="Verify and set the 'copy' variables">
if [[ $cp == true ]]; then
  path_from=${positional_args[1]};
  path_to=${positional_args[2]};

  if [[ -z $path_to ]] && [[ -n $path_from ]]; then
    path_to="${path_from}";
    path_from="${name_pattern}";
    name_pattern="";
  fi

  if [[ -z $path_from ]]; then
    echo "specify the path to copy FROM";
    exit 1;
  fi

  if [[ -z $path_to ]]; then
    echo "specify the path to copy TO";
    exit 1;
  fi
fi
#</editor-fold>

#<editor-fold desc="Verify and set the 'port_forward' variables">
if [[ $port_forward == true ]]; then
  ports=${positional_args[1]};

  if [[ $name_pattern =~ ^[0-9]+(:[0-9]+)?$ ]]; then
    ports="${name_pattern}";
    name_pattern="";
  fi

  if [[ $ports =~ ^[0-9]+$ ]]; then
    ports="${ports}:${ports}";
  fi

  if [[ -z $ports || ! $ports =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "specify the ports to forward from/to (ex. \"3333:3306\")";
    exit 1;
  fi
fi
#</editor-fold>

# ----- Get the list of pods for specific namespace -----
list=$(kubectl -n "${namespace}" get "${list_type}");
get_list_item;

if [[ $list_and_exit == true ]]; then
  exit 0;
fi

read_list_index;
choice=${input_array[$list_idx]};

# ----- Collect kubectl arguments -----
ARGS=("-n" "$namespace");

echo;
if [[ ${exec} == true ]]; then
  echo -e "entering ${namespace}://${choice}\n";
  ARGS+=("exec" "-it" "$choice" "--" "$default_shell");
elif [[ ${cp} == true ]]; then
  echo -e "copying ${namespace}://${choice}:${path_from} to ${path_to}\n";
  ARGS+=("cp" "${choice}:${path_from}" "$path_to");
elif [[ ${port_forward} == true ]]; then
  echo -e "forwarding ${namespace}://${choice} ${ports}\n";
  [[ $list_type == "service" ]] && from="service/${choice}" || from=${choice}
  ARGS+=("port-forward" "${from}" "${ports}");
elif [[ ${remove_pod} == true ]]; then
  echo -e "deleting POD ${namespace}://${choice}\n";
  ARGS+=("delete" "pod" "${choice}");
else
  ARGS+=("logs" "--since=${default_log_time}" "-f" "$choice");
#  ARGS+=("logs" "-f" "$choice");
fi

echo kubectl "${ARGS[@]}"
echo

# ----- Execute -----
kubectl "${ARGS[@]}";
