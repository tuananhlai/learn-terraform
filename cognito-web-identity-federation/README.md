# Cognito Web Identity Federation

Source: <https://github.com/acantril/learn-cantrill-io-labs/tree/master/aws-cognito-web-identity-federation>

## Overview

This is an application that only display private images to authenticated users. The user uses Google as an identity provider.

More specifically, the application obtains an access token from Google, then exchange it to AWS credentials by calling Cognito. Finally, it uses the AWS credentials to fetch images from a private S3 bucket.