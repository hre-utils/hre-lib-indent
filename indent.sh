#!/bin/bash
# indent.sh
#
# Takes strings of texts, appends to a single-line string to allow for parsing
# with only a single call to `sed`. Hopefully improving speed.
#
# Need to think through the pre/post processing. What things should be done
# at each stage? What is the 'processing' stage actually look like, such that
# the pre/post stages would be necessary?
#
#───────────────────────────────────( todo )────────────────────────────────────
# Allow the user to specify the name of the buffer to create. Use an associative
# array, mapping buffer name to the text string. If no name is specified, use a
# 'default' buffer key.
#
# Allow "add" to take an int paramater, which indents the text that's added
#═══════════════════════════════════════════════════════════════════════════════

#──────────────────────────────────( prereqs )──────────────────────────────────
# Version requirement: >4
[[ ${BASH_VERSION%%.*} -lt 4 ]] && {
   echo -e "\n[${BASH_SOURCE[0]}] ERROR: Requires Bash version >= 4\n"
   exit 1
}

# Verification if we've sourced this in other scripts. Name is standardized.
# e.g., filename 'mk-conf.sh' --> '__source_mk_conf=true'
__fname__="$( basename "${BASH_SOURCE[0]%.*}" )"
declare "__source_${__fname__//[^[:alnum:]]/_}__"=true


#══════════════════════════════════╡ GLOBALS ╞══════════════════════════════════
# Establish 'buffer' we can push bits of text onto. Once we've input all the
# data, we can process. Should be split into __pre, __processing__, and __post
# phases.
__buffer__=''


#═════════════════════════════════╡ FUNCTIONS ╞═════════════════════════════════
#──────────────────────────────────( private )──────────────────────────────────
# There aren't really 'private' and 'public' methods, though these will be the
# ones with easier names, though potentially may collide with the user's name-
# space. Hence trying to make double-underscore 'hidden' names for most methods.

# Set defaults:
__strip_newlines__=false
__strip_comments__=false

# Allows for setting options for how we're processing the 'buffer'. Stripping
# empty newlines, or comments, from the text? Maybe more processing options we
# can add later.
function __buffer_config__ {
   while [[ $# -gt 0 ]] ; do
      case $1 in
         '--strip-newlines') shift ; __strip_newlines__=true ;;
         '--strip-comments') shift ; __strip_comments__=true ;;
         *) shift ;;
      esac
   done
}


function __buffer_push__ {
   local input="$@"

   # Breaks on first non-whitespace line
   while IFS=$'\n' read -r line ; do               # Just to be safe--
      [[ "$line" == $'\n' ]] && continue           # Cover all possible cases
      [[ "$line" == '' ]]    && continue           # in which we could have
      [[ "$line" =~ ^\ *$ ]] && continue           # leading empty space.
      break   
   done <<< "$input"
   
   local _line=${line%%[^[:space:]]*}
   local count=$(wc -w <<< ${_line// /. })

   # Have to do this shit here to get around '$(...)' bash's annoying 'feature'
   # of stripping *trailing* newlines of a command. Can read into it by
   # splitting on NUL character, and unsetting IFS.
   local tmp_buffer
   IFS= read -rd '' tmp_buffer < <(sed -E "s#^\s{0,$count}##" <<< "$input")

   __buffer__+="$tmp_buffer"
} 


function __buffer_pre_processing__ {
   local tmp_buffer

   while IFS=$'\n' read -r line ; do
      $__strip_newlines__ && {
         [[ "$line" == $'\n' ]] && continue
         [[ "$line" == '' ]]    && continue
         [[ "$line" =~ ^\ *$ ]] && continue
      }

      $__strip_comments__ && {
         line="${line%%#*}"
      }

      tmp_buffer+="${tmp_buffer+$'\n'}$line"
   done <<< "$__buffer__"

   __buffer__="$tmp_buffer"
}


function __buffer_add_indentation__ {
   local spaces
   local level=$1 

   for i in $(seq 1 $level) ; do
      spaces+=' '
   done

   sed "s,^,$spaces," <<< "$__buffer__"

   # TODO: Trying to improve speed. The below is slightly faster, though we end
   #       up with an extra newline after each buffer. Hmm.
   #readarray -d $'\n' buffer <<< "${__buffer__}"
   #echo -e "${buffer[@]/#/$spaces}"
}

#──────────────────────────────────( public )───────────────────────────────────
function .buf {
   case $1 in
      conf|config)
            shift;
            __buffer_config__ $@
            ;;

      new|reset)
            __buffer__=''
            ;;

      push|add) 
            shift;
            __buffer_push__ "$@"
            ;;

      get|print)
            __buffer_pre_processing__
            echo -e "$__buffer__"
            ;;

      indent)
            # Print text, with optionally specified indent, and optionally add
            # more text prior to printing.
            shift;
            if [[ $1 =~ ^[[:digit:]]+$ ]] ; then
               local level=$1 ; shift
            fi

            if [[ -n $1 ]] ; then
               __buffer_push__ "$@"
            fi

            __buffer_pre_processing__
            __buffer_add_indentation__ ${level:-0}
            ;;

      oneoff)
            # For printing oneoff indented lines. Resets the buffer, prints at
            # the specified level of indentation (if applicable).
            # TODO: should use recursion, just call `.buf reset ; .buf indent`
            shift
            if [[ $1 =~ ^[[:digit:]]+$ ]] ; then
               local level=$1 ; shift
            fi

            __buffer__=''
            __buffer_push__ $@
            __buffer_pre_processing__
            __buffer_add_indentation__ ${level:-0}
            __buffer__=''
            ;;

      *)
            echo ".buf method '$1' does not exist."
            ;;
   esac
}
