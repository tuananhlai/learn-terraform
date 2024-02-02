import json

def lambda_handler(event, context):
    # Echoing back the input
    output_data = {'echoed_input': event}
    
    # Returning the result
    return {
        'statusCode': 200,
        'body': json.dumps(output_data)
    }
