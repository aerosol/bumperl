all: deps compile test escript

deps:
	@rebar get-deps

compile:
	@rebar compile

test:
	@rebar eunit

escript:
	@rebar escript
