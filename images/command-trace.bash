# A command record is produced only when Bash returns to its prompt. Terminal
# replies, paste markers and input consumed by editors never enter this channel.
if [[ ${DQ_TERMINAL_ID:-} =~ ^[0-9a-f]{32}$ ]]; then
    __dq_trace_pipe="${DQ_TRACE_DIRECTORY:-/tmp}/dq-trace-${DQ_TERMINAL_ID}"
    if (umask 077; mkfifo -- "$__dq_trace_pipe"); then
        exec {__dq_trace_fd}<>"$__dq_trace_pipe"
        __dq_history_number='' __dq_prompt_seen=0
        HISTCONTROL='' HISTIGNORE=''
        __dq_trace_command() {
            local status=$?
            local record number command
            record=$(HISTTIMEFORMAT='' builtin history 1)
            if [[ $record =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.*)$ ]]; then
                number=${BASH_REMATCH[1]} command=${BASH_REMATCH[2]}
                if [[ $__dq_prompt_seen == 1 && $number != "$__dq_history_number" ]]; then
                    builtin printf '%s\0' "$command" >&"$__dq_trace_fd"
                fi
                __dq_history_number=$number
            fi
            __dq_prompt_seen=1
            return "$status"
        }
        PROMPT_COMMAND+=(__dq_trace_command)
        trap __dq_trace_command EXIT
    fi
fi
