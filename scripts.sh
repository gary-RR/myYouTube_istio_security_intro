#!/bin/bash

#**Note: This assumes that you already have istio installed on your machine. If you don't istio, 
# wtach my istio into video: https://youtu.be/x_HRl-Ehvb8 where I walk through the installtion process
#

export INGRESS_PORT;
export SECURE_INGRESS_PORT;
export INGRESS_HOST;  
export GATEWAY_URL;
export GATEWAY_CLUSTERIP;
export RATINGS_POD_NAME;
export PRODUCT_POD_NAME;
export DETAILS_POD_NAME
export TEST_POD_NAME;

#Install sample app
    #Create a new name space
    kubectl create namespace books
    #Enable istio for this name space 
    kubectl label namespace books istio-injection=enabled
    
    #cd to where your istio install files are first.
    #Deploy the sample app's containers and create its services
    kubectl apply -f ./istio-1.11.0/samples/bookinfo/platform/kube/bookinfo.yaml -n books 
    #Verify
    kubectl get services -n books

    #Open the services to the outside world
    kubectl apply -f ./istio-1.11.0/samples/bookinfo/networking/bookinfo-gateway.yaml -n books
      
    #Set the INGRESS_HOST and INGRESS_PORT variables for accessing the gateway
    GATEWAY_CLUSTERIP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.clusterIP}')
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
    #GATEWAY_URL
    GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
    #Ensure an IP address and port were successfully assigned to the environment variable
    echo "http://$GATEWAY_URL"

    #Veriy app
    curl -s "http://${GATEWAY_URL}/productpage" | grep -o "<title>.*</title>"

    #Get "ratings" POD name
    RATINGS_POD_NAME=$(kubectl get pods --no-headers -n books | awk '{ print $1}' | grep ratings)

    #Get "product" POD name
    PRODUCT_POD_NAME=$(kubectl get pods --no-headers -n books | awk '{ print $1}' | grep product)

    #GET "details" POD name and IP
    DETAILS_POD_NAME=$(kubectl get pods --no-headers -n books | awk '{ print $1}' | grep details)
    DETAILS_POD_IP=$(kubectl get pods -no-headers -n books -o wide | grep details-v1 | awk '{print $6}')
        
    #Deploy a test POD to test the service
    kubectl create deployment test  --image=gcr.io/google-samples/hello-app:1.0
    #Get POD name
    TEST_POD_NAME=$(kubectl get pods --no-headers | awk '{ print $1}' | grep test)
    #Install curl on the test POD
    kubectl exec -it $TEST_POD_NAME  -- apk --no-cache add curl


#********************************************************* Require "Strict" mutual TLS **********************************
#Call the "details" service
kubectl exec -it $TEST_POD_NAME -- curl http://details.books.svc.cluster.local:9080/details/1

#Require m-tls throughout the "books" namespace. 
    kubectl apply -f ./istio-security/strict-auth.yaml -n books         
    #Call the "details" service again
    kubectl exec -it $TEST_POD_NAME -- curl http://details.books.svc.cluster.local:9080/details/1
    
    #Note that from whitin the "books" namespace, we can use "http". The proxy upgrades it to "https" 
    kubectl exec -it $RATINGS_POD_NAME -n books -- curl  http://details.books.svc.cluster.local:9080/details/1 

#********************************************************* Disable mutual TLS per workload **********************************

#Permit non-mTLS traffic for the "details" service (all ports)
    kubectl apply -f ./istio-security/allow-non-mtls-details-all-ports.yaml
        
    #This call will now succeed    
    kubectl exec -it $TEST_POD_NAME -- curl http://details.books.svc.cluster.local:9080/details/1
    #This call still fails
    kubectl exec -it $TEST_POD_NAME -- curl http://ratings.books.svc.cluster.local:9080/ratings/1

#Permit non-mTLS traffic for the "details" service (on port 9080 only)
    #Delete previous policy
    kubectl delete PeerAuthentication allow-non-mtls-details-all-ports -n books
    #Verify policy effects
    kubectl exec -it $TEST_POD_NAME -- curl http://details.books.svc.cluster.local:9080/details/1
    #Apply new policy
    kubectl apply -f ./istio-security/disable-mtls-details-port-9080.yaml -n books
    #Verify policy effects
    kubectl exec -it $TEST_POD_NAME -- curl http://details.books.svc.cluster.local:9080/details/1

#****************************************************************Set service authorization***********************************

#Call "details" service from "ratings" POD.
kubectl exec -it $RATINGS_POD_NAME -n books -- curl http://details.books.svc.cluster.local:9080/details/1  

#Apply a rule that only "product" page can call "details" service    
    kubectl apply -f ./istio-security/allow-access-to-reviews-from-product.yaml -n books
       
    kubectl exec -it $RATINGS_POD_NAME -n books -- curl http://details.books.svc.cluster.local:9080/details/1

#************************************************************End-user authentication****************************************************

#Apply a rule that only users with valid jwt tokens issued by "my-jwts-server" providers are allowed to log-in
    kubectl apply -f ./istio-security/lock-dwon-product-page.yaml -n books       

    TOKEN=$(curl https://raw.githubusercontent.com/istio/istio/release-1.6/security/tools/jwt/samples/demo.jwt -s) && echo "$TOKEN" | cut -d '.' -f2 - | base64 --decode -
   
    curl --header "Authorization: Bearer $TOKEN" http://${GATEWAY_URL}/productpage  

cleanup

#****************************************************************************************************************************************************
function cleanup()
{
    kubectl delete ns books
}

