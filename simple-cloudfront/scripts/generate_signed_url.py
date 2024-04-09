# https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/cloudfront.html#generate-a-signed-url-for-amazon-cloudfront

import datetime
from botocore.signers import CloudFrontSigner
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding

path = "/private/20240315002839.png"
private_key_path = "./keys/private_key.pem"

# REPLACE WITH THE OUTPUT VALUES FROM THE TERRAFORM TEMPLATE.
key_pair_id = "K3H6ZT4Y8M7OYY"
cloudfront_domain_name = "d33iyrciquqphk.cloudfront.net"

def rsa_signer(message):
    with open(private_key_path, 'rb') as key_file:
        private_key = serialization.load_pem_private_key(
            key_file.read(),
            password=None,
            backend=default_backend()
        )
    return private_key.sign(message, padding.PKCS1v15(), hashes.SHA1())

signer = CloudFrontSigner(key_pair_id, rsa_signer)
expire_date = datetime.datetime.now() + datetime.timedelta(days=7)

signed_url = signer.generate_presigned_url(
    url=f"https://{cloudfront_domain_name}{path}",
    date_less_than=expire_date,
    # Optional: add custom policy if needed
    # policy=my_custom_policy,
)

print("Signed URL:", signed_url)
