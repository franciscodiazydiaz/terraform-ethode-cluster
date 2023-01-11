#
# Lambda function that manages the list of nodes in the Prio Load Balancer.
# The function needs improvents and lacks validation checks.
#
import os
import time

import boto3
import logging
import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(event)

    priolb_endpoint = os.environ['PRIOLB_ENDPOINT']

    ec2 = boto3.resource('ec2')
    instance = ec2.Instance(event['detail']['instance-id'])
    instance_ip = instance.private_ip_address
    # TODO: Execution port is hardcoded
    execution_node = f"http://{instance_ip}:8545"

    logger.info(f"InstanceId: {instance.instance_id}")
    logger.info(f"IPAddress: {instance.private_ip_address}")
    logger.info(f"Execution node: {execution_node}")

    data = {"uri": execution_node}
    if event['detail']['state'] == "running":
        # Giving some boot time to Geth
        logger.info("Sleeping for 60s")
        time.sleep(60)
        logger.info(f"POST data={data} {priolb_endpoint}")
        response = requests.post(priolb_endpoint, json=data)
    elif event['detail']['state'] in ["shutting-down", "stopping"]:
        logger.info(f"DELETE data={data} {priolb_endpoint}")
        response = requests.delete(priolb_endpoint, json=data)

    logger.info(f"Response Status Code: {response.status_code}, Text: {response.text}")
