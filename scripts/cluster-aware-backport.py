#!/usr/bin/env python3
"""
Backport cluster-aware IRQ optimization to Linux 6.18.x lib/group_cpus.c
Based on Wangyang Guo's patch for Linux 6.20+

This script programmatically applies the cluster-aware optimization by:
1. Extracting alloc_groups_to_nodes() from alloc_nodes_groups()
2. Adding assign_cpus_to_groups() helper function
3. Adding alloc_cluster_groups() and __try_group_cluster_cpus()
4. Modifying __group_cpus_evenly() to use cluster-aware logic
"""

import sys
import re

def backport_cluster_aware(filepath):
    """Apply cluster-aware backport to lib/group_cpus.c"""

    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {filepath} not found")
        return False

    # Check if already applied
    if '__try_group_cluster_cpus' in content:
        print("✓ Cluster-aware optimization already present")
        return True

    lines = content.split('\n')

    # Step 1: Find key function locations
    alloc_nodes_start = None
    group_cpus_evenly_start = None

    for i, line in enumerate(lines):
        if 'static void alloc_nodes_groups(unsigned int numgrps,' in line:
            alloc_nodes_start = i
        if 'static int __group_cpus_evenly(unsigned int startgrp' in line:
            group_cpus_evenly_start = i

    if not alloc_nodes_start or not group_cpus_evenly_start:
        print("Error: Could not find required functions")
        return False

    print(f"Found alloc_nodes_groups at line {alloc_nodes_start + 1}")
    print(f"Found __group_cpus_evenly at line {group_cpus_evenly_start + 1}")

    # Step 2: Split alloc_nodes_groups into two functions
    # Find the sort() call
    sort_line = None
    for i in range(alloc_nodes_start, min(alloc_nodes_start + 50, len(lines))):
        if 'sort(node_groups, nr_node_ids,' in lines[i]:
            sort_line = i
            break

    if not sort_line:
        print("Error: Could not find sort() in alloc_nodes_groups")
        return False

    # Find end of alloc_nodes_groups
    alloc_nodes_end = None
    brace_count = 0
    started = False
    for i in range(alloc_nodes_start, len(lines)):
        if '{' in lines[i]:
            brace_count += lines[i].count('{')
            started = True
        if '}' in lines[i]:
            brace_count -= lines[i].count('}')
        if started and brace_count == 0:
            alloc_nodes_end = i
            break

    # Extract the algorithm section (from sort to end)
    algorithm_section = lines[sort_line:alloc_nodes_end]

    # Create new alloc_groups_to_nodes function
    new_function = [
        'static void alloc_groups_to_nodes(unsigned int numgrps,',
        '\t\t\t\t unsigned int numcpus,',
        '\t\t\t\t struct node_groups *node_groups,',
        '\t\t\t\t unsigned int num_nodes)',
        '{',
        '\tunsigned int n, remaining_ncpus = numcpus;',
        ''
    ]

    # Modify algorithm section to use num_nodes instead of nr_node_ids
    # Also need to keep the variable declarations in the for loop
    for line in algorithm_section:
        modified = line.replace('nr_node_ids', 'num_nodes')
        # Don't remove the ngroups, ncpus declarations - they're needed in the loop
        new_function.append(modified)

    new_function.append('}')
    new_function.append('')

    # Insert new function before alloc_nodes_groups
    lines[alloc_nodes_start:alloc_nodes_start] = new_function

    # Update indices
    offset = len(new_function)
    alloc_nodes_start += offset
    alloc_nodes_end += offset
    group_cpus_evenly_start += offset

    # Modify alloc_nodes_groups to use numcpus and call alloc_groups_to_nodes
    # Change "unsigned n, remaining_ncpus = 0;" to "unsigned int n, numcpus = 0;"
    for i in range(alloc_nodes_start, alloc_nodes_end):
        if 'unsigned n, remaining_ncpus = 0;' in lines[i]:
            lines[i] = '\tunsigned int n, numcpus = 0;'
        if 'remaining_ncpus += ncpus;' in lines[i]:
            lines[i] = lines[i].replace('remaining_ncpus += ncpus', 'numcpus += ncpus')

    # Find the min_t line and replace everything after it with the new ending
    min_t_line = None
    for i in range(alloc_nodes_start, alloc_nodes_end):
        if 'numgrps = min_t(unsigned,' in lines[i]:
            min_t_line = i
            break

    if min_t_line:
        new_ending = [
            '',
            '\tnumgrps = min_t(unsigned int, numcpus, numgrps);',
            '\talloc_groups_to_nodes(numgrps, numcpus, node_groups, nr_node_ids);',
            '}'
        ]
        lines[min_t_line:alloc_nodes_end+1] = new_ending

    print("✓ Step 1: Created alloc_groups_to_nodes() and modified alloc_nodes_groups()")

    # Step 3: Add assign_cpus_to_groups function after alloc_nodes_groups
    assign_cpus_lines = [
        '',
        'static void assign_cpus_to_groups(unsigned int ncpus,',
        '\t\t\t\t struct cpumask *nmsk,',
        '\t\t\t\t struct node_groups *nv,',
        '\t\t\t\t struct cpumask *masks,',
        '\t\t\t\t unsigned int *curgrp,',
        '\t\t\t\t unsigned int last_grp)',
        '{',
        '\tunsigned int v, cpus_per_grp, extra_grps;',
        '\t/* Account for rounding errors */',
        '\textra_grps = ncpus - nv->ngroups * (ncpus / nv->ngroups);',
        '',
        '\t/* Spread allocated groups on CPUs of the current node */',
        '\tfor (v = 0; v < nv->ngroups; v++, *curgrp += 1) {',
        '\t\tcpus_per_grp = ncpus / nv->ngroups;',
        '',
        '\t\t/* Account for extra groups to compensate rounding errors */',
        '\t\tif (extra_grps) {',
        '\t\t\tcpus_per_grp++;',
        '\t\t\t--extra_grps;',
        '\t\t}',
        '',
        '\t\t/*',
        '\t\t * wrapping has to be considered given \'startgrp\'',
        '\t\t * may start anywhere',
        '\t\t */',
        '\t\tif (*curgrp >= last_grp)',
        '\t\t\t*curgrp = 0;',
        '\t\tgrp_spread_init_one(&masks[*curgrp], nmsk, cpus_per_grp);',
        '\t}',
        '}',
        ''
    ]

    # Find alloc_nodes_groups again (indices changed)
    lines = '\n'.join(lines).split('\n')
    alloc_nodes_new_start = None
    for i, line in enumerate(lines):
        if 'static void alloc_nodes_groups(unsigned int numgrps,' in line:
            alloc_nodes_new_start = i
            break

    # Find its end properly - track brace depth
    if alloc_nodes_new_start:
        brace_depth = 0
        in_function = False
        for i in range(alloc_nodes_new_start, len(lines)):
            if '{' in lines[i]:
                brace_depth += lines[i].count('{')
                in_function = True
            if '}' in lines[i]:
                brace_depth -= lines[i].count('}')
            if in_function and brace_depth == 0:
                # Found the actual end of alloc_nodes_groups
                lines[i+1:i+1] = assign_cpus_lines
                print("✓ Step 2: Added assign_cpus_to_groups()")
                break

    # Step 4: Add cluster detection functions before __group_cpus_evenly
    cluster_functions = """
static int alloc_cluster_groups(unsigned int ncpus,
\t\t\t        unsigned int ngroups,
\t\t\t        struct cpumask *node_cpumask,
\t\t\t        cpumask_var_t msk,
\t\t\t        const struct cpumask ***clusters_ptr,
\t\t\t        struct node_groups **cluster_groups_ptr)
{
\tunsigned int ncluster = 0;
\tunsigned int cpu, nc, n;
\tconst struct cpumask *cluster_mask;
\tconst struct cpumask **clusters;
\tstruct node_groups *cluster_groups;

\tcpumask_copy(msk, node_cpumask);

\t/* Probe how many clusters in this node. */
\twhile (1) {
\t\tcpu = cpumask_first(msk);
\t\tif (cpu >= nr_cpu_ids)
\t\t\tbreak;

\t\tcluster_mask = topology_cluster_cpumask(cpu);
\t\tif (!cpumask_weight(cluster_mask))
\t\t\tgoto no_cluster;
\t\t/* Clean out CPUs on the same cluster. */
\t\tcpumask_andnot(msk, msk, cluster_mask);
\t\tncluster++;
\t}

\t/* If ngroups < ncluster, cross cluster is inevitable, skip. */
\tif (ncluster == 0 || ncluster > ngroups)
\t\tgoto no_cluster;

\t/* Allocate memory based on cluster number. */
\tclusters = kcalloc(ncluster, sizeof(struct cpumask *), GFP_KERNEL);
\tif (!clusters)
\t\tgoto no_cluster;
\tcluster_groups = kcalloc(ncluster, sizeof(struct node_groups), GFP_KERNEL);
\tif (!cluster_groups)
\t\tgoto fail_cluster_groups;

\t/* Filling cluster info for later process. */
\tcpumask_copy(msk, node_cpumask);
\tfor (n = 0; n < ncluster; n++) {
\t\tcpu = cpumask_first(msk);
\t\tcluster_mask = topology_cluster_cpumask(cpu);
\t\tnc = cpumask_weight_and(cluster_mask, node_cpumask);
\t\tclusters[n] = cluster_mask;
\t\tcluster_groups[n].id = n;
\t\tcluster_groups[n].ncpus = nc;
\t\tcpumask_andnot(msk, msk, cluster_mask);
\t}

\talloc_groups_to_nodes(ngroups, ncpus, cluster_groups, ncluster);

\t*clusters_ptr = clusters;
\t*cluster_groups_ptr = cluster_groups;
\treturn ncluster;

 fail_cluster_groups:
\tkfree(clusters);
 no_cluster:
\treturn 0;
}

/*
 * Try group CPUs evenly for cluster locality within a NUMA node.
 *
 * Return: true if success, false otherwise.
 */
static bool __try_group_cluster_cpus(unsigned int ncpus,
\t\t\t\t    unsigned int ngroups,
\t\t\t\t    struct cpumask *node_cpumask,
\t\t\t\t    struct cpumask *masks,
\t\t\t\t    unsigned int *curgrp,
\t\t\t\t    unsigned int last_grp)
{
\tstruct node_groups *cluster_groups;
\tconst struct cpumask **clusters;
\tunsigned int ncluster;
\tbool ret = false;
\tcpumask_var_t nmsk;
\tunsigned int i, nc;

\tif (!zalloc_cpumask_var(&nmsk, GFP_KERNEL))
\t\tgoto fail_nmsk_alloc;

\tncluster = alloc_cluster_groups(ncpus, ngroups, node_cpumask, nmsk,
\t\t\t\t       &clusters, &cluster_groups);

\tif (ncluster == 0)
\t\tgoto fail_no_clusters;

\tfor (i = 0; i < ncluster; i++) {
\t\tstruct node_groups *nv = &cluster_groups[i];

\t\t/* Get the cpus on this cluster. */
\t\tcpumask_and(nmsk, node_cpumask, clusters[nv->id]);
\t\tnc = cpumask_weight(nmsk);
\t\tif (!nc)
\t\t\tcontinue;
\t\tWARN_ON_ONCE(nv->ngroups > nc);

\t\tassign_cpus_to_groups(nc, nmsk, nv, masks, curgrp, last_grp);
\t}

\tret = true;
\tkfree(cluster_groups);
\tkfree(clusters);
 fail_no_clusters:
\tfree_cpumask_var(nmsk);
 fail_nmsk_alloc:
\treturn ret;
}
"""

    # Find __group_cpus_evenly again
    lines = '\n'.join(lines).split('\n')
    group_cpus_start = None
    for i, line in enumerate(lines):
        if 'static int __group_cpus_evenly(unsigned int startgrp' in line:
            group_cpus_start = i
            break

    if group_cpus_start:
        lines.insert(group_cpus_start, cluster_functions)
        print("✓ Step 3: Added alloc_cluster_groups() and __try_group_cluster_cpus()")

    # Step 5: Modify __group_cpus_evenly to use cluster-aware logic
    lines = '\n'.join(lines).split('\n')

    # Find __group_cpus_evenly again
    for i, line in enumerate(lines):
        if 'static int __group_cpus_evenly(unsigned int startgrp' in line:
            # Fix variable declaration
            for j in range(i, i + 10):
                if 'unsigned int i, n, nodes, cpus_per_grp, extra_grps, done = 0;' in lines[j]:
                    lines[j] = '\tunsigned int i, n, nodes, done = 0;'
                    break

            # Find the for loop and modify it
            for j in range(i, i + 100):
                if 'for (i = 0; i < nr_node_ids; i++)' in lines[j]:
                    # Change "unsigned int ncpus, v;" to "unsigned int ncpus;"
                    for k in range(j, j + 10):
                        if 'unsigned int ncpus, v;' in lines[k]:
                            lines[k] = '\t\tunsigned int ncpus;'

                            # Find WARN_ON_ONCE and replace the section after it
                            for m in range(k, k + 50):
                                if 'WARN_ON_ONCE(nv->ngroups > ncpus);' in lines[m]:
                                    # Find the done += line
                                    done_line = None
                                    for n in range(m, m + 30):
                                        if '\t\tdone += nv->ngroups;' in lines[n]:
                                            done_line = n
                                            break

                                    if done_line:
                                        # Replace the section
                                        new_logic = [
                                            '',
                                            '\t\tif (__try_group_cluster_cpus(ncpus, nv->ngroups, nmsk,',
                                            '\t\t\t\t\t     masks, &curgrp, last_grp)) {',
                                            '\t\t\tdone += nv->ngroups;',
                                            '\t\t\tcontinue;',
                                            '\t\t}',
                                            '',
                                            '\t\tassign_cpus_to_groups(ncpus, nmsk, nv, masks, &curgrp,',
                                            '\t\t\t\t      last_grp);'
                                        ]
                                        lines[m+1:done_line] = new_logic
                                        print("✓ Step 4: Modified __group_cpus_evenly() to use cluster-aware logic")
                                    break
                            break
                    break
            break

    # Write modified content
    output = '\n'.join(lines)
    with open(filepath, 'w') as f:
        f.write(output)

    print(f"\n✓ Successfully backported cluster-aware IRQ optimization")
    return True

if __name__ == '__main__':
    filepath = sys.argv[1] if len(sys.argv) > 1 else 'lib/group_cpus.c'
    success = backport_cluster_aware(filepath)
    sys.exit(0 if success else 1)
