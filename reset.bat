@echo off
minikube start
echo Deleting all pods in all namespaces (this may break kube-system temporarily)...
kubectl delete pod --all --all-namespaces --ignore-not-found
minikube stop
