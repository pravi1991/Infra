import json
import urllib3
import os
import boto3
from twilio.rest import Client

def get_secrets():
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name='us-east-1'
    )
    
    try:
        secret_response = client.get_secret_value(
            SecretId=os.environ['SECRETS_ARN']
        )
        secrets = json.loads(secret_response['SecretString'])
        return secrets
    except Exception as e:
        print(f"Error fetching secrets: {str(e)}")
        raise e

def send_slack_notification(message, is_critical=False):
    secrets = get_secrets()
    slack_message = {
        "text": ":rotating_light: CRITICAL AWS Billing Alert! :rotating_light:" if is_critical else ":warning: AWS Billing Warning",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"{'*CRITICAL* ' if is_critical else ''}*AWS Billing Alert*\n"
                           f"Account: {message.get('AWSAccountId')}\n"
                           f"Region: {message.get('Region')}\n"
                           f"Alarm: {message.get('AlarmName')}\n"
                           f"Description: {message.get('AlarmDescription')}\n"
                           f"State: {message.get('NewStateValue')}"
                }
            }
        ]
    }

    http = urllib3.PoolManager()
    response = http.request(
        'POST',
        secrets['slack_webhook_url'],
        body=json.dumps(slack_message),
        headers={'Content-Type': 'application/json'}
    )
    return response

def make_twilio_call():
    secrets = get_secrets()
    client = Client(secrets['twilio_account_sid'], secrets['twilio_auth_token'])
    
    call = client.calls.create(
        twiml='<Response><Say>Alert! AWS billing has exceeded 10 dollars. Please check your AWS console immediately.</Say></Response>',
        to=secrets['twilio_to_number'],
        from_=secrets['twilio_from_number']
    )
    return call.sid

def handler(event, context):
    try:
        message = json.loads(event['Records'][0]['Sns']['Message'])
        
        # Determine if this is a critical alert based on the alarm name
        is_critical = 'critical' in message.get('AlarmName', '').lower()
        
        # Always send Slack notification
        slack_response = send_slack_notification(message, is_critical)
        
        # If critical (>$10), also make a phone call
        call_sid = None
        if is_critical:
            call_sid = make_twilio_call()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'slack_status': slack_response.status,
                'call_sid': call_sid
            })
        }
    except Exception as e:
        print(f"Error processing notification: {str(e)}")
        raise e