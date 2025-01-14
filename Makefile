.PHONY: all build

all: build

# This logic was moved from upstream/hack/build-images.sh - too much changing logic
# and became hard to maintain
build:
	docker build -t ghcr.io/converged-computing/flux-service:latest .

push: build
	docker push ghcr.io/converged-computing/flux-service:latest
	
.PHONY:
proto:
	# pip install grpcio-tools
	# pip freeze | grep grpcio-tools
	mkdir -p ensemble/protos
	cd ensemble/protos
	# We run python first, then protoc to get around https://github.com/protocolbuffers/protobuf/issues/18096
	python -m grpc_tools.protoc -I./protos --python_out=./ensemble/protos --pyi_out=./ensemble/protos --grpc_python_out=./ensemble/protos ./protos/ensemble-service.proto
	protoc -I=./protos --python_out=./ensemble/protos ./protos/ensemble-service.proto
	sed -i 's/import ensemble_service_pb2 as ensemble__service__pb2/from . import ensemble_service_pb2 as ensemble__service__pb2/' ./ensemble/protos/ensemble_service_pb2_grpc.py


# Assume testing with kind
install:
	kubectl delete -f ./daemonset-installer.yaml || true
	kubectl apply -f ./daemonset-installer.yaml
