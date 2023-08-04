platform-start:
	kubectl apply -f platform.yaml

platform-stop:
	kubectl delete deployment silimate-platform-k8s

platform-destroy:
	kubectl delete -f platform.yaml
