#!/usr/bin/env bash

oc delete clusterservicebrokers.servicecatalog.k8s.io summit-broker

if [ "$1" = "build" ]; then
    oc start-build broker --from-dir=.
fi

oc create -f broker.yml