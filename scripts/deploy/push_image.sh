#!/bin/bash

############################################################################
# Description
# This script has two roles to build Docker Image, and, on the other hand,
# to push into  Elastic Container Registory.
############################################################################

set -eu

trap catch ERR

# send slack notification for deployment
function send_slack () {
    # 環境
    environment=${1}
    # システム名
    system_name=${2}
    # 日付の取得
    date=$(date "+%Y/%m/%d %H:%M:%S")
    # キューURL
    queue_url=${3}
    # ステータスの取得
    status=${4}
    # ターゲットカラーの取得
    target_color=${5}
    # gitlogの取得
    gitlog=$(git --no-pager log -1 --no-merges --pretty=format:"[%ad] %h %an : %s" --date=format:'%Y/%m/%d %H:%M:%S')

    # json形式に整形
    message="{
        \"system_name\":\"${system_name}\",
        \"environment\":\"${environment}\",
        \"status\":\"${status}\",
        \"time\":\"${date}\",
        \"target_color\":\"${target_color}\",
        \"gitlog\":\"${gitlog}\"
    }"

    # キュー送信
    aws sqs send-message \
    --queue-url ${queue_url} \
    --message-body "${message}" \
    --message-group-id "${system_name}:${environment}" \
    --region "ap-northeast-1" > /dev/null
}

function catch {
    send_slack ${env} ${cluster} ${send_queue} "FAILED" ""
}

function check_account () {
    aws_account_id=${1}

    echo 'AWSアカウントチェック...'
    if aws sts get-caller-identity| grep ${aws_account_id} > /dev/null ; then
        echo 'OK';
    else
        echo 'NG'
        echo 'AWSアカウントを切り替えてから実行してください。'
        echo 'e.g. export AWS_PROFILE=<プロファイル名>'
        exit 1
    fi
}

project=$1;
env=$2;

echo "--- Start ${project} deploy ---"

# build配下を削除
npm run clean

case "${env}" in
    "prod")
        echo "--- Start push docker image for production ---"
        readonly account_id="845168618390";
        # PVS命名規則
        readonly cluster="${project}-web-${env}"
        readonly listener=$(aws elbv2 describe-load-balancers --region ap-northeast-1 |jq -r '.LoadBalancers[].LoadBalancerArn' | grep ${cluster} | xargs -I lbarn aws elbv2 describe-listeners --region ap-northeast-1 --load-balancer-arn lbarn | jq -r '.Listeners[] | select(.Protocol == "HTTPS") | .ListenerArn');
        readonly registory_uri="${account_id}.dkr.ecr.ap-northeast-1.amazonaws.com"
        readonly repository="${registory_uri}/${cluster}"
        readonly send_queue="https://sqs.ap-northeast-1.amazonaws.com/${account_id}/play-store-prod-send-deploy-message-queue.fifo"
        send_slack ${env} ${cluster} ${send_queue} "START" ""
        echo "--- Start build src ---"
        npm run bundle -- --release
        ;;
    "stg")
        echo "--- Start push docker image for staging ---"
        readonly account_id="179017469188";
        # PVS命名規則
        readonly cluster="${project}-web-${env}"
        readonly listener=$(aws elbv2 describe-load-balancers --region ap-northeast-1 |jq -r '.LoadBalancers[].LoadBalancerArn' | grep ${cluster} | xargs -I lbarn aws elbv2 describe-listeners --region ap-northeast-1 --load-balancer-arn lbarn | jq -r '.Listeners[] | select(.Protocol == "HTTPS") | .ListenerArn');
        readonly registory_uri="${account_id}.dkr.ecr.ap-northeast-1.amazonaws.com"
        readonly repository="${registory_uri}/${cluster}"
        readonly send_queue="https://sqs.ap-northeast-1.amazonaws.com/${account_id}/pvs-b-stg-send-deploy-message-queue.fifo"
        send_slack ${env} ${cluster} ${send_queue} "START" ""
        echo "--- Start build src ---"
        npm run bundle -- --staging
        ;;
    *)
    echo "--- Error !! ---"
    echo "Please arg prod or stg ."
    false
    exit 2
esac

# AWSアカウントチェック
check_account ${account_id}

set +eu

if [ -n "$3" ]; then
    readonly bgcolor=$3
    case "${bgcolor}" in
        *blue*)
            readonly color="blue"
            echo "Force deployment color is blue."
            ;;
        *green*)
            readonly color="green"
            echo "Force deployment color is green."
            ;;
        *)
        echo "--- Error !! ---"
        echo "Please arg blue or green ."
        false
        exit 2
    esac
else
    # Variables this script uses.
    readonly active_targetgroup=$(aws elbv2 describe-rules --region ap-northeast-1 --listener-arn ${listener} | grep -e TargetGroupArn -e Weight | grep -B1 '"Weight": 1' | grep -m1 TargetGroupArn)

    # check the side of color where active target group is running.
    echo "--- check which color is on service ---"
    case ${active_targetgroup} in
        *blue*)
            readonly color="green"
            echo "Service is on the side of blue."
            ;;
        *green*)
            readonly color="blue"
            echo "Service is on the side of green."
            ;;
        *)
            readonly color="no"
            echo "Service is on Unknown."
    esac
fi

set -eu

readonly git_commit=`git log --pretty=oneline | head -n 1 | awk '{print $1}'`
# readonly login_ecr=`aws ecr get-login --region ap-northeast-1 --no-include-email`

# Alert when this script can not judge the color that is on services.
if [ ${color} = "no" ]; then
    echo "!!  ERROER  !!"
    echo "This error means that this script can not get which color is on serivice."
    echo "Be sure that immediatly you should check if the server is running."
    false
    exit 2
fi


# Login into ECR for preparing to push Docker Image.
echo ""
echo "--- login ECS Registory ---"

aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${registory_uri}

# Build Docker Image.
echo ""
echo "--- start to docker build ---"
echo "Docker is going to build for ${color}"
echo ""

# for preview. env to prod
if [ "$env" = "preview" ]; then
    env="prod"
fi

#docker build --no-cache=true -t ${repository}:${git_commit} -t ${repository}:${env}-${color} .
docker build -t ${repository}:${git_commit} -t ${repository}:${env}-${color} .
if [ ! $? -eq 0 ]; then
    echo "Error while building docker images." && false
    exit 2
fi

# Push Docker Image into ECR.
echo ""
echo "--- start to docker push ---"
echo "docker is going to push image of ${color}"
for image in ${repository}:${env}-${color} ${repository}:${git_commit} ;do
    docker push ${image}
    if [ ! $? -eq 0 ]; then
        echo "Error while pushing docker images." && false
        exit 2
    fi
done

echo ""
echo "force deployment ${color} side."
aws ecs update-service --region ap-northeast-1 --cluster ${cluster} --service ${cluster}-${color} --force-new-deployment > /dev/null

echo ""
echo "Please switch alb to ${color}."

echo "--- END ---"

send_slack ${env} ${cluster} ${send_queue} "SUCCEEDED" ${color}
