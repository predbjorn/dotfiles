
mkdir -p Hacking 
cd Hacking
if [ ! -d ReactNative/helseoversikt_rn ]; then
	mkdir -p ReactNative
	cd ReactNative
	git clone git@github.com:Helseoversikt/helseoversikt_rn.git helseoversikt_rn;
	cd ..
fi
if [ ! -d React/partnerPortal ]; then
	mkdir -p React
	cd React
	git clone git@github.com:Helseoversikt/helseoversikt-api.git ho_server;
	git clone git@github.com:Helseoversikt/helseoversikt-reactjs.git ho_client;
	cd ..
fi
if [ ! -d projects/foundation ]; then
	mkdir -p projects/foundation/
	cd projects/foundation
	git clone git@github.com:predbjorn/foundation_sanity.git found_sanity;
	git clone git@github.com:predbjorn/foundation_web.git found_web;
	git clone git@github.com:predbjorn/foundation_app.git foundation;
	cd ../..;
fi
if [ ! -d projects/foundation ]; then
	mkdir -p projects/foundation/;
	cd projects/foundation;
	git clone git@github.com:predbjorn/tren-web-cleint.git tren_client;
	git clone git@github.com:predbjorn/tren-web-server.git tren_server;
	cd ../..;
fi


