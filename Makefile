pg-start:
	kubectl apply -f pg-configmap.yaml
	kubectl apply -f pg-storage.yaml
	kubectl apply -f pg-deployment.yaml
	kubectl apply -f pg-service.yaml

pg-stop:
	kubectl delete service postgres 
	kubectl delete deployment postgres
	kubectl delete configmap postgres-config
	kubectl delete persistentvolumeclaim postgres-pv-claim
	kubectl delete persistentvolume postgres-pv-volume

postgres-start:
	kubectl apply -f postgres.yaml

postgres-stop:
	kubectl delete -f postgres.yaml

platform-start:
	kubectl apply -f platform.yaml

platform-stop:
	kubectl delete -f platform.yaml
