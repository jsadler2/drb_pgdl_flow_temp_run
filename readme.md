To run this on Tallgrass I do

```
nohup snakemake --cluster "sbatch -A {cluster.account} -t {cluster.time} -p {cluster.partition} -N {cluster.nodes} -n 1 {cluster.gpu}" -p -k -j 40 --cluster-config ~/cluster_config.yml --rerun-incomplete --configfile config.yml -T 0  > run.out &
```
