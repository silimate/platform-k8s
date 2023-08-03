# REFERENCE
pg-start:
	kubectl apply -f reference/pg-configmap.yaml
	kubectl apply -f reference/pg-storage.yaml
	kubectl apply -f reference/pg-deployment.yaml
	kubectl apply -f reference/pg-service.yaml

pg-stop:
	kubectl delete service postgres 
	kubectl delete deployment postgres
	kubectl delete configmap postgres-config
	kubectl delete persistentvolumeclaim postgres-pv-claim
	kubectl delete persistentvolume postgres-pv-volume

postgres-start:
	kubectl apply -f reference/postgres.yaml

postgres-stop:
	kubectl delete -f reference/postgres.yaml

# PLATFORM
platform-start:
	kubectl apply -f platform.yaml

platform-stop:
	kubectl delete -f platform.yaml
