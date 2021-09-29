#  expectValue = "SUCCESS"
#  scriptTimeout = 3
#  replayEnabled = true
#  replayTimeout = 5

FLAG='FAIL'

if [[ "<SOLUTION TYPE>" == "standalone" ]]; then
    test_instance_id=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bigIpInstanceId") | .OutputValue')
    if [[ <NIC COUNT> == 1 ]]; then
        MGMT_PORT='8443'
    else
        MGMT_PORT='443'
    fi
else
    MGMT_PORT='8443'
    group_name=$(aws autoscaling describe-auto-scaling-groups --region <REGION> | jq -r '.AutoScalingGroups[] |select (.AutoScalingGroupARN |contains("<STACK NAME>"))|.AutoScalingGroupName' | grep 'bigip')
    echo "Autoscale group name: $group_name"

    test_instance_id=$(aws autoscaling describe-auto-scaling-groups --region  <REGION> --auto-scaling-group-name $group_name | jq .AutoScalingGroups[0].Instances[0].InstanceId | tr -d '"')
fi

echo "BIGIP Instance Id: $test_instance_id"
PASSWORD="$test_instance_id"

if [[ "<PROVISION PUBLIC IP>" == "false" ]]; then
    bastion_instance_id=$(aws cloudformation describe-stacks --stack-name <STACK NAME> --region <REGION> | jq -r '.Stacks[].Outputs[] | select (.OutputKey=="bastionInstanceId") | .OutputValue')

    echo "Bastion Name: $bastion_instance_id"

	bastion_ip=$(aws ec2 describe-instances --region <REGION> --instance-ids ${bastion_instance_id} --query "Reservations[*].Instances[*].PublicIpAddress" --output=text)
    bigip_private_ip=$(aws ec2 describe-instances  --region <REGION> --instance-ids $test_instance_id |jq -r '.Reservations[0].Instances[0].PrivateIpAddress')

    echo "Bastion IP: $bastion_ip"
    echo "BIGIP Private Ip: $bigip_private_ip"

    AS3_RESPONSE=$(ssh -o "StrictHostKeyChecking=no" -o ConnectTimeout=7 -i /etc/ssl/private/dewpt_private.pem ubuntu@"$bastion_ip" "curl -skvvu <BIGIP USER>:${PASSWORD} https://${bigip_private_ip}:${MGMT_PORT}/mgmt/shared/appsvcs/declare" | jq -r .)
else
  test_instance_public_ip=$(aws ec2 describe-instances --region  <REGION> --instance-ids $test_instance_id | jq .Reservations[0].Instances[0].PublicIpAddress | tr -d '"')

    echo "BIGIP Public IP: $test_instance_public_ip"

    AS3_RESPONSE=$(curl -sku <BIGIP USER>:${PASSWORD} https://${test_instance_public_ip}:${MGMT_PORT}/mgmt/shared/appsvcs/declare | jq -r .)
fi

echo "AS3_RESPONSE: ${AS3_RESPONSE}"


if echo ${AS3_RESPONSE} | grep -q "Quickstart"; then
    FLAG='SUCCESS'
fi

echo $FLAG