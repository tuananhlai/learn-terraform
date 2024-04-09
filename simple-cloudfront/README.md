# Simple CloudFront

Setup an S3 bucket with public and private objects. The bucket is accessible publicly through CloudFront only. Private objects must be accessed using either URLs or cookies signed with `keys/private_key.pem`.

## Generating signed URLs

Install Python dependencies.

```sh
pip3 install -r ./requirements.txt
```

Replace the designated variable in `scripts/generate_signed_url.py` and run the following command.

```sh
python3 ./scripts/generate_signed_url.py
```

Here's a sample output.

```txt
Signed URL: https://d33iyrciquqphk.cloudfront.net/private/20240315002839.png?Expires=1713303115&Signature=ZYeN7dZbTIvXSelYcVPsqXGbOk1tKY21DdUVlTyGGamxNcAGg5Fv11qQel6jVOE4y3BLAwNkwzgNINwdgItNKsm0psyxY3VVxUNuzdFd3Ly-DTe7BISI-E5XifbUVwTtqFego6J0h~B7mImrp6-E-Nh-VBcV6eikW2~gcsofWDof74HzB~DC3Dw2TJAjZeh4IgbWudYqy8xtPurFm1MRIzm3XUiiYfi9psVatpHARmnZ4PGKWPN8rPfkc8YfPE~zyYPycS3Sahb7YGYHoIF1jzrQhX~XwETB8H994Q5eQDsNn5IAWxgmkF3dW1Bkyg~Kpc07gr1HRi5V4ij28TmXcA__&Key-Pair-Id=K3H6ZT4Y8M7OYY
```