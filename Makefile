.PHONY: all compile clean test xref dialyzer elvis cover coverview edoc help start stop travis-run travis-install

REBAR ?= rebar3
REDIS_VERSION ?= 6.0.1

# Configs
COMMON_CONF=--cluster-enabled yes --cluster-node-timeout 5000 --appendonly yes
NODE1_CONF=$(COMMON_CONF) --port 30001
NODE2_CONF=$(COMMON_CONF) --port 30002
NODE3_CONF=$(COMMON_CONF) --port 30003
NODE4_CONF=$(COMMON_CONF) --port 30004
NODE5_CONF=$(COMMON_CONF) --port 30005
NODE6_CONF=$(COMMON_CONF) --port 30006

all: compile xref elvis

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) clean
	@rm -rf _build

test:
	@ERL_FLAGS="-config test.config" $(REBAR) eunit -v --cover

xref:
	@$(REBAR) xref

dialyzer:
	@$(REBAR) dialyzer

elvis:
	@elvis rock

cover:
	@$(REBAR) cover -v

coverview: cover
	xdg-open _build/test/cover/index.html


edoc:
	@$(REBAR) skip_deps=true doc

help:
	@echo "Please use 'make <target>' where <target> is one of"
	@echo "  start             starts a test redis cluster"
	@echo "  stop              stops all redis servers"
	@echo "  travis-run        starts the redis cluster and runs your tests"
	@echo "  travis-install    install redis from 'unstable' branch"

start:
	docker run --name redis-1 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE1_CONF)
	docker run --name redis-2 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE2_CONF)
	docker run --name redis-3 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE3_CONF)
	docker run --name redis-4 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE4_CONF)
	docker run --name redis-5 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE5_CONF)
	docker run --name redis-6 -d --net=host redis:$(REDIS_VERSION) redis-server $(NODE6_CONF)
	sleep 5
	echo 'yes' | docker run --name redis-cluster -i --rm --net=host redis:$(REDIS_VERSION) \
	redis-cli --cluster create \
	127.0.0.1:30001 127.0.0.1:30002 127.0.0.1:30003 127.0.0.1:30004 127.0.0.1:30005 127.0.0.1:30006 \
	--cluster-replicas 1

stop:
	-docker rm -f redis-1
	-docker rm -f redis-2
	-docker rm -f redis-3
	-docker rm -f redis-4
	-docker rm -f redis-5
	-docker rm -f redis-6

travis-run:
	make start # Start and join cluster
	sleep 5

	make compile && make test

	make stop # Stop all cluster nodes
