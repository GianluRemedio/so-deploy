#!/bin/bash

set -e

bold=$(tput bold)
normal=$(tput sgr0)
underline=$(tput smul)
nounderline=$(tput rmul)

fail() {
  echo -e "\n\nTry ${bold}'./deploy.sh --help'${normal} or ${bold}'./deploy.sh -h'${normal} for more information" >&2
  exit 255
}

if [[ "$*" =~ (^|\ )(-h|-H|--help)($|\ ) ]]; then
  echo "

${bold}NAME${normal}
    ${bold}deploy.sh${normal} - script to deploy sisoputnfrba's TP.

${bold}SYNOPSIS${normal}
    ${bold}deploy.sh${normal} [ ${bold}-t${normal}=${underline}target${nounderline} ] [ ${bold}-s${normal}=${underline}structure${nounderline} ] [ ${bold}-r${normal}=${underline}rule${nounderline} ] [ option=${underline}value${nounderline}... ] ${underline}repository${nounderline}

${bold}DESCRIPTION${normal}
    The ${bold}deploy.sh${normal} utility is to ease the deploy process.

${bold}POSITIONAL ARGUMENTS${normal}
    ${bold}-t | --target${normal}       Changes the directory where the script is executed. By default it will be the current directory.

    ${bold}-s | --structure${normal}    Changes the path where the script should look for makefiles. By default it will be the current directory of each project.

    ${bold}-r | --rule${normal}         Changes the makefile rule for building projects. By default it will be 'all'.

${bold}OPTIONS${normal}
    ${bold}-l | --lib${normal}          Adds an external dependency to build and install.

    ${bold}-d | --dependency${normal}   Adds an internal dependency to build and install from the repository.

    ${bold}-p | --project${normal}      Adds a project to build from the repository.

    ${bold}-c | --config${normal}       Replaces a variable in all configuration files containing it. The format is 'key=value'.

${bold}COMPATIBILITY${normal}
    The repository must be in ${bold}sisoputnfrba${normal} organization and have makefiles to compile each project or dependency.

${bold}EXAMPLE${normal}
      ${bold}./deploy.sh${normal} ${bold}-l${normal}=mumuki/cspec ${bold}-d${normal}=sockets ${bold}-p${normal}=server ${bold}-p${normal}=client -c=IP_SERVER=192.168.0.32 ${underline}tp-2022-1c-example${nounderline}

  "
  exit 1
fi

TARGET=""
case $1 in
  -t=*|--target=*)
    case ${1#*=} in
      /*) TARGET="${1#*=}" ;;
      *) TARGET="$PWD/${1#*=}" ;;
    esac
    shift
  ;;
  *)
  ;;
esac

STRUCTURE=""
case $1 in
  -s=*|--structure=*)
    STRUCTURE="${1#*=}"
    shift
  ;;
  *)
  ;;
esac

RULE="all"
case $1 in
  -r=*|--rule=*)
    RULE="${1#*=}"
    shift
  ;;
  *)
  ;;
esac

if [[ $# -lt 1 ]]; then
  echo -e "\n\n${bold}No repository specified!${normal}" >&2
  fail
fi

LIBRARIES=()
DEPENDENCIES=()
PROJECTS=()
CONFIGURATIONS=()

OPTIONS=("${@:1:$#-1}")
for i in "${OPTIONS[@]}"
do
    case $i in
        -l=*|--lib=*)
          LIBRARIES+=("${i#*=}")
          shift
        ;;
        -d=*|--dependency=*)
          DEPENDENCIES+=("${i#*=}")
          shift
        ;;
        -p=*|--project=*)
          PROJECTS+=("${i#*=}")
          shift
        ;;
        -c=*|--config=*)
          CONFIGURATIONS+=("${i#*=}")
          shift
        ;;
        *)
          echo -e "\n\n${bold}Invalid option:${normal} ${i}" >&2
          fail
        ;;
    esac
done

REPONAME="$1"
if [[ $REPONAME != "tp"* ]]; then
  echo -e "\n\n${bold}Invalid repository${normal}: $REPONAME" >&2
  fail
fi

if [[ $TARGET ]]; then
  echo -e "\n\n${bold}Changing directory:${normal} ${PWD} -> ${bold}$TARGET${normal}"
  cd "$TARGET" || fail
fi

echo -e "\n\n${bold}Installing commons library...${normal}\n\n"

rm -rf "so-commons-library"
git clone --depth=1 --single-branch --recurse-submodules --shallow-submodules git@github.com:sisoputnfrba/so-commons-library.git
make -C "so-commons-library" uninstall install

echo -e "\n\n${bold}Cloning external libraries...${normal}"

for i in "${LIBRARIES[@]}"
do
  echo -e "\n\n${bold}Building ${i}${normal}\n\n"
  rm -rf "${i#*\/}"
  git clone --depth=1 --single-branch "https://github.com/sisoputnfrba/${REPONAME}.git"
  make -C "${i#*\/}"
  sudo make -C "${i#*\/}" install
done

echo -e "\n\n${bold}Cloning project repo...${normal}\n\n"

rm -rf "$REPONAME"
git clone --depth=1 --single-branch "git@github.com:sisoputnfrba/${REPONAME}.git"



echo -e "\n\n${bold}Building dependencies${normal}..."

for i in "${DEPENDENCIES[@]}"
do
  echo -e "\n\n${bold}Building ${i}${normal}\n\n"
  make -C "$REPONAME/$i/$STRUCTURE" "$RULE"
  sudo make -C "$REPONAME/$i/$STRUCTURE" install
done

echo -e "\n\n${bold}Building projects...${normal}"

for i in "${PROJECTS[@]}"
do
  echo -e "\n\n${bold}Building ${i}${normal}\n\n"
  if [[ "$i" =~ ^CPU[0-9]+$ ]]; then
  make -C "$REPONAME/cpu/$STRUCTURE" "$RULE"
else
  make -C "$REPONAME/$i/$STRUCTURE" "$RULE"
fi

done

echo -e "\n\n${bold}Replacing variables...${normal}"

for i in "${CONFIGURATIONS[@]}"
do
  # Si tiene formato CLAVE=VALOR:ARCHIVO
  if [[ "$i" =~ ^([^=]+)=([^:]+):(.+)$ ]]; then
    KEY="${BASH_REMATCH[1]}"
    VALUE="${BASH_REMATCH[2]}"
    TARGET_FILE="${BASH_REMATCH[3]}"
    echo -e "\nReemplazando ${bold}$KEY=$VALUE${normal} solo en ${bold}${TARGET_FILE}.config${normal}...\n"

    FILES=$(find "$REPONAME" -type f -name "${TARGET_FILE}.config" -o -name "${TARGET_FILE}.cfg")
    for file in $FILES; do
      sed -i "s|^\($KEY\s*=\).*|\1$VALUE|" "$file"
    done
  else
    # Reemplazo global en todos los archivos
    KEY="${i%=*}"
    VALUE="${i#*=}"
    echo -e "\nReemplazando ${bold}$KEY=$VALUE${normal} globalmente...\n"

    FILES=$(find "$REPONAME" -type f \( -name "*.config" -o -name "*.cfg" \))
for file in $FILES; do
  if grep -qE "^\s*$KEY\s*=" "$file"; then
    sed -i "s|^\($KEY\s*=\).*|\1$VALUE|" "$file"
    echo "$KEY actualizado en $file"
  fi
done
  fi
done

for i in "${CONFIGURATIONS[@]}"
do
  # Caso: CLAVE=VALOR:ARCHIVO
  if [[ "$i" =~ ^([^=]+)=([^:]+):(.+)$ ]]; then
    KEY="${BASH_REMATCH[1]}"
    VALUE="${BASH_REMATCH[2]}"
    TARGET_FILE="${BASH_REMATCH[3]}"
    
    # Soporte para claves tipo IP_MODULO (ej: IP_KERNEL)
    if [[ "$KEY" =~ ^IP_(.+)$ ]]; then
      KEY="IP"
      TARGET_FILE="${BASH_REMATCH[1],,}"  # en minúsculas
    fi

    echo -e "\nReemplazando ${bold}$KEY=$VALUE${normal} solo en ${bold}${TARGET_FILE}.config${normal}...\n"

    FILES=$(find "$REPONAME" -type f -iname "${TARGET_FILE}.config" -o -iname "${TARGET_FILE}.cfg")
    for file in $FILES; do
      sed -i "s|^\($KEY\s*=\).*|\1$VALUE|" "$file"
    done

  else
    # Reemplazo global en todos los archivos .config/.cfg
    KEY="${i%=*}"
    VALUE="${i#*=}"

    # Soporte también para IP_<MODULO> sin archivo explícito
    if [[ "$KEY" =~ ^IP_(.+)$ ]]; then
      KEY="IP"
      TARGET_FILE="${BASH_REMATCH[1],,}"
      echo -e "\nReemplazando ${bold}IP=$VALUE${normal} solo en ${bold}${TARGET_FILE}/*.config${normal}...\n"

      FILES=$(find "$REPONAME/$TARGET_FILE" -type f \( -iname "*.config" -o -iname "*.cfg" \))
      for file in $FILES; do
        if grep -qE "^\s*IP\s*=" "$file"; then
          sed -i "s|^\(\s*IP\s*=\).*|\1$VALUE|" "$file"
          echo "IP actualizada en $file"
        fi
      done

    else
      echo -e "\nReemplazando ${bold}$KEY=$VALUE${normal} globalmente...\n"
      FILES=$(find "$REPONAME" -type f \( -name "*.config" -o -name "*.cfg" \))
      for file in $FILES; do
        if grep -qE "^\s*$KEY\s*=" "$file"; then
          sed -i "s|^\($KEY\s*=\).*|\1$VALUE|" "$file"
          echo "$KEY actualizado en $file"
        fi
      done
    fi
  fi
done


echo -e "\n\n${bold}Deploy done!${normal}\n\n"
