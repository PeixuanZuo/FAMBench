#!/bin/bash
# sudo sysctl kernel.numa_balancing=0

NODES=${1:-1}
NUM_GPUS=${2:-8}
BS=${3:-8}
EP=${4:-1}

export NODE_COUNT=${NODES}
export BEVT_MAX_STEPS=${5:-1200}
export PYTHONPATH=$(pwd):${PYTHONPATH}
export OMP_NUM_THREADS=1

RANK=${RANK:=0}
MASTER_ADDR=${MASTER_ADDR:=127.0.0.1}
NODE_COUNT=${NODE_COUNT:=1}

DATAROOT=../BEVT_DATA/
pretrained_ckpt=${DATAROOT}/swin_base_image_stream_pretrain.pth
tokenizer_path=${DATAROOT}/dall_e_tokenizer_weight
work_dir=/tmp/swin_base_bevt_twostream

prefix=${DATAROOT}/kinetics/kinetics400_256
image_data_root=${DATAROOT}/ILSVRC2012/train
image_ann_file_train=reduced.ILSVRC2012_name_train_list.txt
repeat_times=5000

data_root=${prefix}/train_256
data_root_val=${prefix}/val_256
ann_file_train=${prefix}/train_256.txt
ann_file_val=${prefix}/val_256.txt
ann_file_test=${prefix}/val_256.txt

# config dict will update according to the specified_configs.
specified_configs="tokenizer_path=${tokenizer_path} model.cls_head.vae_weight_path=${tokenizer_path}
                   model.backbone.pretrained=${pretrained_ckpt}
                   data_root=${data_root} data_root_val=${data_root_val}
                   ann_file_train=${ann_file_train} ann_file_val=${ann_file_val} ann_file_test=${ann_file_test}
                   image_data_root=${image_data_root} image_ann_file_train=${image_ann_file_train}
                   data.videos_per_gpu=${BS} data.omni_videos_per_gpu='['${BS},$[8 * ${BS}]']'
                   data.train.0.ann_file=${ann_file_train} data.train.0.data_prefix=${data_root}
                   data.train.1.times=${repeat_times} data.train.1.dataset.ann_file=${image_ann_file_train}
                   data.train.1.dataset.data_prefix=${image_data_root} total_epochs=${EP}"

echo -e "rank: ${NODE_RANK}\nnode count: ${NODE_COUNT}"
echo -e "master addr: ${MASTER_ADDR}\nmaster port: ${MASTER_PORT}"

cd BEVT/

set -x
python -m torch.distributed.launch --nnodes ${NODE_COUNT} \
     --node_rank ${NODE_RANK} \
     --master_addr ${MASTER_ADDR} \
     --master_port ${MASTER_PORT} \
     --nproc_per_node ${NUM_GPUS} \
     tools/train.py configs/recognition/swin/swin_base_patch244_window877_bevt_in1k_k400.py \
         --launcher pytorch --work-dir ${work_dir} \
         --cfg-options ${specified_configs} \
         --seed 0 --deterministic

python tools/analysis/analyze_logs.py cal_train_time ${work_dir}/*.log.json 2>&1
