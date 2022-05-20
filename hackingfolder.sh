#!/bin/bash

mkdir -p Hacking 
cd Hacking
if [ ! -d ReactNative/helseoversikt_rn ]; then
	mkdir -p ReactNative
	cd ReactNative
	gh repo clone git@github.com:Helseoversikt/helseoversikt_rn.git helseoversikt_rn;
	cd ..
fi
if [ ! -d variables ]; then
	gh repo clone git@github.com:predbjorn/variables.git;
fi
if [ ! -d React/partnerPortal ]; then
	mkdir -p React
	cd React
	gh repo clone git@github.com:Helseoversikt/helseoversikt-api.git ho_server;
	gh repo clone git@github.com:Helseoversikt/helseoversikt-reactjs.git ho_client;
	cd ..
fi
if [ ! -d projects/foundation ]; then
	mkdir -p projects/foundation/
	cd projects/foundation
	gh repo clone git@github.com:predbjorn/foundation_sanity.git found_sanity;
	gh repo clone git@github.com:predbjorn/foundation_web.git found_web;
	gh repo clone git@github.com:predbjorn/foundation_app.git foundation;
	cd ../..;
fi
if [ ! -d projects/foundation ]; then
	mkdir -p projects/foundation/;
	cd projects/foundation;
	gh repo clone git@github.com:predbjorn/tren-web-cleint.git tren_client;
	gh repo clone git@github.com:predbjorn/tren-web-server.git tren_server;
	cd ../..;
fi


