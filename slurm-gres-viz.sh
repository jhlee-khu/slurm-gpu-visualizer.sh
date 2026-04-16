#!/usr/bin/env bash
set -euo pipefail

SHOW_INDEX=0
MINE_ONLY=0
LOOP_SEC=0

usage() {
    cat <<'EOF'
Usage: slurmviz.sh [-i] [-m] [-l SEC]

Options:
  -i        Show GPU indices as [0][1] instead of '*'
  -m        Show only my jobs
  -l SEC    Refresh every SEC seconds
  -h        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            SHOW_INDEX=1
            shift
            ;;
        -m)
            MINE_ONLY=1
            shift
            ;;
        -l)
            shift
            [[ $# -gt 0 ]] || { echo "Error: -l requires a number" >&2; exit 1; }
            [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: -l requires an integer" >&2; exit 1; }
            LOOP_SEC="$1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

run_once() {
    local tmp_nodes tmp_jobs
    tmp_nodes=$(mktemp)
    tmp_jobs=$(mktemp)
    trap 'rm -f "$tmp_nodes" "$tmp_jobs"' RETURN

    local USE_COLOR NC BOLD DIM RED GREEN YELLOW BLUE MAGENTA CYAN WHITE GRAY
    if [[ -t 1 ]]; then
        USE_COLOR=1
    else
        USE_COLOR=0
    fi

    if [[ "${USE_COLOR}" -eq 1 ]]; then
        NC=$'\033[0m'
        BOLD=$'\033[1m'
        DIM=$'\033[2m'
        RED=$'\033[31m'
        GREEN=$'\033[32m'
        YELLOW=$'\033[33m'
        BLUE=$'\033[34m'
        MAGENTA=$'\033[35m'
        CYAN=$'\033[36m'
        WHITE=$'\033[37m'
        GRAY=$'\033[90m'
    else
        NC=''
        BOLD=''
        DIM=''
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        WHITE=''
        GRAY=''
    fi

    scontrol show node -o > "$tmp_nodes"

    if [[ "$MINE_ONLY" -eq 1 ]]; then
        squeue -h -t R -u "$USER" -o "%i" | while read -r jid; do
            [[ -n "$jid" ]] || continue
            scontrol show job -d "$jid"
            echo
        done > "$tmp_jobs"
    else
        squeue -h -t R -o "%i" | while read -r jid; do
            [[ -n "$jid" ]] || continue
            scontrol show job -d "$jid"
            echo
        done > "$tmp_jobs"
    fi

    awk \
    -v NC="$NC" \
    -v BOLD="$BOLD" \
    -v DIM="$DIM" \
    -v RED="$RED" \
    -v GREEN="$GREEN" \
    -v YELLOW="$YELLOW" \
    -v BLUE="$BLUE" \
    -v MAGENTA="$MAGENTA" \
    -v CYAN="$CYAN" \
    -v WHITE="$WHITE" \
    -v GRAY="$GRAY" \
    -v SHOW_INDEX="$SHOW_INDEX" \
    '
    function trim(s){ sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }

    function memmb_to_gib_str(mb) { return sprintf("%.0f GiB", mb / 1024.0) }
    function memnode_to_gib_str(mb) { return sprintf("%.2f", mb / 1024.0) }

    function parse_node_line(line,    n,i,a,k,v,pos,node,m) {
        delete KV
        n = split(line, a, /[ \t]+/)
        for (i=1; i<=n; i++) {
            pos = index(a[i], "=")
            if (pos > 0) {
                k = substr(a[i],1,pos-1)
                v = substr(a[i],pos+1)
                KV[k]=v
            }
        }

        node = KV["NodeName"]
        if (node == "") return

        cputot[node] = KV["CPUTot"] + 0
        memtot[node] = KV["RealMemory"] + 0
        nodestate[node] = KV["State"]

        gputot[node] = 0
        if (match(KV["Gres"], /gpu(:[^:]+)?:([0-9]+)/, m)) gputot[node] = m[2] + 0

        if (!(node in seen_node)) {
            seen_node[node] = 1
            nodes[++node_count] = node
        }
    }

    function add_gpu_slots(node, idxspec, owner,    parts,n,i,a,j) {
        if (idxspec == "") return 0
        n = split(idxspec, parts, /,/)
        cnt = 0
        for (i=1; i<=n; i++) {
            if (parts[i] ~ /^[0-9]+-[0-9]+$/) {
                split(parts[i], a, "-")
                for (j=a[1]; j<=a[2]; j++) {
                    gpu_slot_owner[node, j] = owner
                    cnt++
                }
            } else if (parts[i] ~ /^[0-9]+$/) {
                gpu_slot_owner[node, parts[i]+0] = owner
                cnt++
            }
        }
        return cnt
    }

    function ord(ch) {
        return index("\
 !\"#$%&'\''()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", ch) + 31
    }

    function hash_user(user,    i,h,c) {
        h = 0
        for (i = 1; i <= length(user); i++) {
            c = ord(substr(user, i, 1))
            h = (h * 131 + c + i) % 2147483647
        }
        return h
    }

    function abs(x) { return x < 0 ? -x : x }

    function init_palette(    i,code) {
        if (palette_inited) return
        palette_inited = 1

        split("196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201 200 199 198 197 203 209 215 221 227 191 155 119 83 84", pal_codes, " ")

        palette_size = 40
        for (i = 1; i <= palette_size; i++) {
            code = pal_codes[i]
            palette[i] = sprintf("\033[38;5;%sm", code)
        }

        for (i=1; i<=palette_size; i++) {
            if (i <= 6) palette_group[i] = 1
            else if (i <= 12) palette_group[i] = 2
            else if (i <= 19) palette_group[i] = 3
            else if (i <= 24) palette_group[i] = 4
            else if (i <= 30) palette_group[i] = 5
            else palette_group[i] = 6
        }
    }

    function group_distance(g1, g2,    d) {
        d = abs(g1 - g2)
        if (d > 3) d = 6 - d
        return d
    }

    function count_distinct_users(    k,n) {
        n = 0
        for (k in seen_users) n++
        return n
    }

    function choose_palette_index(user,    h,start,step,attempt,idx,g,score,bestScore,bestIdx,usedN,penalty,j,otherIdx,otherGroup,localPenalty) {
        init_palette()

        h = hash_user(user)
        start = (h % palette_size) + 1
        step  = ((int(h / 97) % (palette_size - 1)) + 1)

        bestScore = -1
        bestIdx = start
        usedN = count_distinct_users()

        for (attempt = 0; attempt < palette_size; attempt++) {
            idx = ((start - 1 + attempt * step) % palette_size) + 1
            g = palette_group[idx]

            penalty = 0

            for (j in used_palette_idx) {
                otherIdx = used_palette_idx[j]
                otherGroup = palette_group[otherIdx]

                if (g == otherGroup) penalty += 12
                else if (group_distance(g, otherGroup) == 1) penalty += 5
            }

            for (j in user_color_idx) {
                if (user_color_idx[j] == idx) penalty += 50
            }

            localPenalty = ((h + idx * 17 + attempt * 29) % 97)
            score = 1000 - penalty + localPenalty

            if (score > bestScore) {
                bestScore = score
                bestIdx = idx
            }

            if (usedN < 6 && penalty == 0) break
        }

        return bestIdx
    }

    function user_color(user,    idx) {
        init_palette()

        if (!(user in user_color_map)) {
            idx = choose_palette_index(user)
            user_color_map[user] = palette[idx]
            user_color_idx[user] = idx
            used_palette_idx[user] = idx
            seen_users[user] = 1
        }
        return user_color_map[user]
    }

    function empty_gpu_symbol(state,    s) {
        s = toupper(state)

        if (SHOW_INDEX == 1) {
            if (s ~ /DOWN/ || s ~ /FAIL/ || s ~ /NOT_RESPONDING/) {
                return RED " ■ " NC
            }
            if (s ~ /DRAIN/ || s ~ /DRNG/ || s ~ /RESERVED/) {
                return YELLOW " ■ " NC
            }
            return GRAY " - " NC
        }

        if (s ~ /DOWN/ || s ~ /FAIL/ || s ~ /NOT_RESPONDING/) {
            return RED "■" NC
        }
        if (s ~ /DRAIN/ || s ~ /DRNG/ || s ~ /RESERVED/) {
            return YELLOW "■" NC
        }
        return GRAY "-" NC
    }

    function gpu_used_symbol(owner, g) {
        if (SHOW_INDEX == 1) return user_color(owner) sprintf("[%d]", g) NC
        return user_color(owner) "*" NC
    }

    function gpu_used_symbol_fallback(g) {
        if (SHOW_INDEX == 1) return CYAN sprintf("[%d]", g) NC
        return CYAN "*" NC
    }

    BEGIN {
        RS=""
        FS="\n"
        BARW=8
    }

    FILENAME == ARGV[1] {
        for (i=1; i<=NF; i++) parse_node_line($i)
        next
    }

    FILENAME == ARGV[2] {
        jobid=""; user=""; name=""; node=""; cpus=0; memmb=0; idx=""; gpucnt=0

        for (i=1; i<=NF; i++) {
            line = $i

            if (line ~ /^JobId=/) {
                if (match(line, /JobId=([0-9]+)/, m)) jobid = m[1]
                if (match(line, /JobName=([^ ]+)/, m)) name = m[1]
            }
            if (line ~ /UserId=/) {
                if (match(line, /UserId=([^ (]+)/, m)) user = m[1]
            }
            if (line ~ /NumCPUs=/) {
                if (match(line, /NumCPUs=([0-9]+)/, m)) cpus = m[1] + 0
            }
            if (line ~ /AllocTRES=/) {
                if (match(line, /gres\/gpu=([0-9]+)/, m)) gpucnt = m[1] + 0
                if (match(line, /mem=([0-9]+)([MGT])/, mm)) {
                    if (mm[2] == "M") memmb = mm[1] + 0
                    else if (mm[2] == "G") memmb = (mm[1] + 0) * 1024
                    else if (mm[2] == "T") memmb = (mm[1] + 0) * 1024 * 1024
                }
            }
            if (line ~ /^[ \t]*Nodes=/) {
                if (match(line, /Nodes=([^ ]+)/, m)) node = m[1]
                if (match(line, /Mem=([0-9]+)/, m) && memmb == 0) memmb = m[1] + 0
                if (match(line, /IDX:([0-9,-]+)/, m)) idx = m[1]
            }
        }

        if (node != "") {
            cpuused[node] += cpus
            memused[node] += memmb
            used = add_gpu_slots(node, idx, user)
            if (used == 0) gpuused[node] += gpucnt

            L++
            legend_user[L] = user
            legend_jobid[L] = jobid
            legend_name[L] = name
            legend_node[L] = node
            legend_idx[L] = (idx == "" ? "-" : idx)
            legend_cpus[L] = cpus
            legend_mem[L] = memmb_to_gib_str(memmb)
            legend_color[L] = user_color(user)
        }
    }

    END {
        for (i=1; i<=node_count; i++) {
            node = nodes[i]
            bar = ""
            used = 0

            for (g=0; g<BARW; g++) {
                if (g < gputot[node]) {
                    if ((node SUBSEP g) in gpu_slot_owner) {
                        owner = gpu_slot_owner[node, g]
                        bar = bar gpu_used_symbol(owner, g)
                        used++
                    } else {
                        bar = bar empty_gpu_symbol(nodestate[node])
                    }
                } else {
                    if (SHOW_INDEX == 1) bar = bar "   "
                    else bar = bar " "
                }
            }

            if (used == 0 && gpuused[node] > 0) {
                used = gpuused[node]
                bar = ""
                for (g=0; g<BARW; g++) {
                    if (g < gputot[node]) {
                        if (g < used) bar = bar gpu_used_symbol_fallback(g)
                        else bar = bar empty_gpu_symbol(nodestate[node])
                    } else {
                        if (SHOW_INDEX == 1) bar = bar "   "
                        else bar = bar " "
                    }
                }
            }

            printf "%s%-8s%s: [GPU] [%d/%d] %-28s [CPU] %4d/%-4d [MEM] %4d/%s GiB\n",
                BOLD, node, NC,
                used, gputot[node], bar,
                cpuused[node]+0, cputot[node]+0,
                int(memused[node]/1024.0 + 0.5), memnode_to_gib_str(memtot[node])
        }

        print ""
        print BOLD "=================================================== LEGEND ===================================================" NC
        printf "%-10s %-16s %-8s %-34s %-10s %-10s %-8s %-10s\n",
            "COLORS","USER_ID","JOB_ID","JOB_NAME","NODE_NAME","GPUS","CPUS","MEM"

        for (i=1; i<=L; i++) {
            printf "%s%-10s%s %-16s %-8s %-34s %-10s %-10s %-8d %-10s\n",
                legend_color[i], "********", NC,
                legend_user[i],
                legend_jobid[i],
                substr(legend_name[i],1,34),
                legend_node[i],
                legend_idx[i],
                legend_cpus[i],
                legend_mem[i]
        }

        print ""
        print BOLD "EMPTY GPU SYMBOL" NC ": " RED "■" NC " down/fail/not responding   " YELLOW "■" NC " drain/drng/reserved   " GRAY "-" NC " normal empty"
        if (SHOW_INDEX == 1) {
            print BOLD "GPU BAR MODE" NC ": [index]"
        } else {
            print BOLD "GPU BAR MODE" NC ": stars"
        }
    }
    ' "$tmp_nodes" "$tmp_jobs"
}

if [[ "$LOOP_SEC" -gt 0 ]]; then
    while true; do
        clear
        run_once
        sleep "$LOOP_SEC"
    done
else
    run_once
fi