import os

# this is needed for running on HPC if using GPU
shell.prefix("module load analytics cuda10.1/toolkit/10.1.105 \n \
              run_training -e /home/jsadler/.conda/envs/rgcn --no-node-list")

# add scripts dir to path

from river_dl.preproc_utils import prep_data
from river_dl.postproc_utils import predict_from_weights, combined_metrics, plot_obs
from river_dl.train import train_model

out_dir = config['out_dir']
code_dir = config['code_dir']

rule all:
    input:
        expand("{outdir}/{metric_type}_metrics.csv",
                outdir=out_dir,
                metric_type=['overall', 'month', 'reach', 'month_reach'],
        ),
        expand( "{outdir}/{plt_variable}_{partition}.png",
                outdir=out_dir,
                plt_variable=['temp', 'flow'],
                partition=['trn', 'val'],
        ),
        f"{out_dir}/archive.gz",

rule prep_io_data:
    input:
         config['obs_temp'],
         config['obs_flow'],
         config['sntemp_file'],
         config['dist_matrix'],
    output:
        "{outdir}/prepped.npz"
    run:
        prep_data(input[0], input[1], input[2], input[3],
                  x_vars=config['x_vars'],
                  catch_prop_file=None,
                  exclude_file=None,
                  train_start_date=config['train_start_date'],
                  train_end_date=config['train_end_date'],
                  val_start_date=config['val_start_date'],
                  val_end_date=config['val_end_date'],
                  test_start_date=config['test_start_date'],
                  test_end_date=config['test_end_date'],
                  primary_variable=config['primary_variable'],
                  log_q=False, segs=None,
                  out_file=output[0])


 #use "train" if wanting to use GPU on HPC
rule train:
    input:
        "{outdir}/prepped.npz"
    output:
        directory("{outdir}/trained_weights/"),
        directory("{outdir}/pretrained_weights/"),
    params:
         #getting the base path to put the training outputs in
         #I omit the last slash (hence '[:-1]' so the split works properly
        run_dir=lambda wildcards, output: os.path.split(output[0][:-1])[0],
        pt_epochs=config['pt_epochs'],
        ft_epochs=config['ft_epochs'],
        lamb=config['lamb'],
    group: 'train_predict_evaluate'
    shell:
        """
        "python {code_dir}/train_model.py -o {params.run_dir} -i {input[0]} -p {params.pt_epochs} -f {params.ft_epochs} --lamb {params.lamb} --model rgcn -s 135"
        """

 #use "train_model" if wanting to use CPU or local GPU
#rule train_model_local_or_cpu:
    #input:
        #"{outdir}/prepped.npz"
    #output:
        #directory("{outdir}/trained_weights/"),
        #directory("{outdir}/pretrained_weights/"),
    #params:
         ##getting the base path to put the training outputs in
         ##I omit the last slash (hence '[:-1]' so the split works properly
        #run_dir=lambda wildcards, output: os.path.split(output[0][:-1])[0],
    #run:
        #train_model(input[0], config['pt_epochs'], config['ft_epochs'], config['hidden_size'],
                    #params.run_dir, model_type='rgcn', lamb=config['lamb'])

rule make_predictions:
    input:
        "{outdir}/trained_weights/",
        "{outdir}/prepped.npz"
    output:
        "{outdir}/{partition}_preds.feather",
    group: 'train_predict_evaluate'
    run:
        model_dir = input[0] + '/'
        predict_from_weights(model_type='rgcn', model_weights_dir=model_dir,
                             hidden_size=config['hidden_size'], io_data=input[1],
                             partition=wildcards.partition, outfile=output[0],
                             logged_q=False)


def get_grp_arg(wildcards):
    if wildcards.metric_type == 'overall':
        return None
    elif wildcards.metric_type == 'month':
        return 'month'
    elif wildcards.metric_type == 'reach':
        return 'seg_id_nat'
    elif wildcards.metric_type == 'month_reach':
        return ['seg_id_nat', 'month']


rule combine_metrics:
    input:
         config['obs_temp'],
         config['obs_flow'],
         "{outdir}/trn_preds.feather",
         "{outdir}/val_preds.feather"
    output:
         "{outdir}/{metric_type}_metrics.csv"
    group: 'train_predict_evaluate'
    params:
        grp_arg = get_grp_arg
    run:
        combined_metrics(obs_temp=input[0],
                         obs_flow=input[1],
                         pred_trn=input[2],
                         pred_val=input[3],
                         grp=params.grp_arg,
                         outfile=output[0])


rule plot_prepped_data:
    input:
        "{outdir}/prepped.npz",
    output:
        "{outdir}/{variable}_{partition}.png",
    run:
        plot_obs(input[0], wildcards.variable, output[0],
                 partition=wildcards.partition)


rule archive_files:
    input:
        "Snakefile",
        "config.yml",
        "/home/jsadler/.conda/envs/dlenv/lib/python3.7/site-packages/river_dl/"
    output:
        "{outdir}/archive.gz"
    shell:
        """
        tar zcvf {output} {input}
        """

