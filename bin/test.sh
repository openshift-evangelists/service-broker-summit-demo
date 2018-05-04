#!/bin/bash

PROJECT="brokerdemo"

oc login -u developer -p developer

oc delete project $PROJECT

while oc get project $PROJECT | grep $PROJECT; do
 echo "Waiting for $PROJECT cleanup"
 sleep 5
done

oc new-project $PROJECT

oc new-app -e RACK_ENV=development --name=broker ruby~`pwd`
oc expose svc broker
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:$PROJECT:default