.PHONY: all ligato-run ligato-stop etcd vpp-agent

all:
	@echo "Try following:"
	@echo 'alias ee="docker exec -it etcd etcdctl"'
	@echo 'alias vv="docker exec -it vpp-agent vppctl -s /run/vpp/cli.sock"'
	@echo 'alias aa="docker exec -it vpp-agent agentctl"'

ligato-run:
	docker-compose -f ligato.yaml up -d

ligato-stop:
	docker-compose -f ligato.yaml down


etcd:
	docker run --rm --name etcd -p 2379:2379 -e ETCDCTL_API=3 quay.io/coreos/etcd /usr/local/bin/etcd -advertise-client-urls http://0.0.0.0:2379 -listen-client-urls http://0.0.0.0:2379

vpp-agent:
	docker run -it --rm --name vpp-agent -p 5002:5002 -p 9191:9191 --privileged ligato/vpp-agent
