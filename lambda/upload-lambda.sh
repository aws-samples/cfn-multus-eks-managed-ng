#!/bin/bash

BUCKET=$1 # bucket name
FILENAME="eks-mng-multus-lambda.zip" # upload key

zip -r -q $FILENAME lambda_function.py
echo "Uploading to S3"
aws s3 cp $FILENAME s3://$BUCKET/$FILENAME
echo "https://s3.amazonaws.com/$BUCKET/$FILENAME"


