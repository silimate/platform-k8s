platform-start:
	kubectl apply -f platform.yaml

platform-stop:
	kubectl delete -f platform.yaml
