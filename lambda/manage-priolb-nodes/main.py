#
# Lambda function that manages the list of nodes in the Prio Load Balancer.
# The function needs improvents and lacks validation checks.
#
import os
import time

import boto3
import logging
import requests
#from requests.adapters import HTTPAdapter, Retry

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(event)

    priolb_endpoint = os.environ["PRIOLB_ENDPOINT"]
    execution_node_port = os.environ.get("EXECUTIONNODE_PORT", "8545")

    ec2 = boto3.resource("ec2")
    instance = ec2.Instance(event["detail"]["instance-id"])
    instance_ip = instance.private_ip_address
    execution_node = f"http://{instance_ip}:{execution_node_port}"

    logger.info(f"Execution InstanceId: {instance.instance_id}")
    logger.info(f"Execution IPAddress: {execution_node}")

    data = {"uri": execution_node}
    if event["detail"]["state"] == "running":
        # Giving Geth some time to boot
        retries = 20
        sleep_time = 10
        for retry in range(retries):
            logger.info(f"Trying to connect to Execution node: {retry} of {retries}")

            try:
                res = requests.get(execution_node, timeout=5)
            except requests.ConnectionError as e:
                logger.error(e)
                time.sleep(sleep_time)
                continue

            if res.status_code == 200:
                break
            else:
                logger.info(f"{execution_node} responded {res.status_code}, sleeping {sleep_time}s")
                time.sleep(sleep_time)

        #s = requests.Session()
        #retries = Retry(total=10, backoff_factor=2, status_forcelist=[200])#[500, 502, 503, 504])
        #s.mount('http://', HTTPAdapter(max_retries=retries))
        #s.get(execution_node)

        logger.info(f"POST data={data} {priolb_endpoint}")
        response = requests.post(priolb_endpoint, json=data, timeout=10)
    elif event["detail"]["state"] in ["shutting-down", "stopping"]:
        logger.info(f"DELETE data={data} {priolb_endpoint}")
        response = requests.delete(priolb_endpoint, json=data, timeout=10)

    logger.info(f"Response Status Code: {response.status_code}, Text: {response.text}")
