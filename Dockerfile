FROM ubuntu:16.04
MAINTAINER Disy IT <it@disy.net>

# TODO:
# - Set rasdaman log dir and tomcat log dir to shared folder

ENV CATALINA_HOME /opt/tomcat
ENV WEBAPPS_HOME $CATALINA_HOME/webapps
ENV RMANHOME /opt/rasdaman/
ENV HOSTNAME rasdaman-dev1
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV R_LIBS /home/rasdaman/R
ENV RASDATA ${RMANHOME}data 

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
RUN env


# Install required software 
RUN apt-get -qq update && apt-get install --no-install-recommends --fix-missing -y --force-yes \
	ssh \
	openssh-server \
	sudo \
	wget \
	gdebi \
	git \
	make \
	autoconf \
	automake \
	libtool \
	gawk \
	flex \
	bison \
	g++ \
	ant \
	autotools-dev \
	comerr-dev \
	libecpg-dev \
	libtiff5-dev \
	libgdal-dev \
	libgdal1-dev \
	gdal-bin \
	python-gdal \
	libncurses5-dev \
	libnetpbm10-dev \
	libtool \
	m4 \
	postgresql-9.5 \
	openjdk-8-jdk \
	libtiff-dev \
	libjpeg8-dev \
	libpng12-dev \
	libnetpbm10-dev \
	libhdf5-dev \
	libnetcdf-dev \
	libnetcdf-cxx-legacy-dev \
	libnetcdf-c++4 \
	libnetcdf-c++4-dev \
	supervisor \
	libproj-dev \ 
	libedit-dev \
	nano \
	tomcat8




# Install latest R version  # Not required if R package MODIS is not used, older version via apt is sufficient then
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9 && echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/" >> /etc/apt/sources.list
RUN apt-get update && apt-get install --fix-missing -y --force-yes r-base r-base-dev
RUN R CMD javareconf && Rscript --vanilla -e 'install.packages(c("rJava", "testthat"), repos="http://cran.rstudio.com/")'

# Install RStudio Server
RUN wget https://download2.rstudio.org/rstudio-server-1.0.44-amd64.deb && gdebi -n rstudio-server-1.0.44-amd64.deb


# Install Tomcat6
RUN wget -t 3 -w 2 http://apache.mirrors.ionfish.org/tomcat/tomcat-8/v8.5.5/bin/apache-tomcat-8.5.5.tar.gz
RUN tar -xzf apache-tomcat-8.5.5.tar.gz
RUN mv apache-tomcat-8.5.5 /opt/tomcat


# create rasdaman user with credentials: rasdaman:rasdaman
RUN adduser --gecos "" --disabled-login --home /home/rasdaman rasdaman \
   && echo  "rasdaman:rasdaman" | chpasswd \
   && adduser rasdaman sudo # add to sudo group

   
# change login credentials for root and postgres users
RUN echo 'root:xxxx.xxxx.xxxx' | chpasswd && echo 'postgres:xxxx.xxxx.xxxx' | chpasswd


# Configure SSH
RUN mkdir /var/run/sshd 
RUN echo 'StrictHostKeyChecking no' >> /etc/ssh/ssh_config




# Download and build rasdaman
RUN mkdir /home/rasdaman/install && git clone -q git://rasdaman.org/rasdaman.git /home/rasdaman/install
WORKDIR /home/rasdaman/install

# Dependencies of rasnet protocol # TODO
RUN apt-get install --fix-missing -y --force-yes --no-install-recommends libprotobuf-dev libzmq-dev protobuf-compiler libboost-all-dev

RUN apt-get install --fix-missing -y --force-yes --no-install-recommends curl maven


## 2015-01-29: BUGFIX WITH libsqlite3 (make fails because -lsqlite3 is set before objects)
RUN cp /usr/lib/x86_64-linux-gnu/libsqlite* /usr/lib/ # is this really neccessary?
RUN sed -i 's!LDFLAGS="$LDFLAGS $SQLITE3_LDFLAGS"!LDADD="$LDADD $SQLITE3_LDFLAGS"!' configure.ac
####


#RUN git checkout v9.0.5 # uncomment this if you want a tagged rasdaman version
RUN autoreconf -fi  && LIBS="-lsqlite3" ./configure --prefix=$RMANHOME --with-netcdf --with-hdf4 --with-wardir=$WEBAPPS_HOME --with-default-basedb=sqlite --enable-r --with-filedatadir=${RMANHOME}data

#--enable-rasnet # TODO

RUN make && make install

#Hack for: cp: cannot stat '../../java/dist/rasj.jar': No such file or directory
RUN sed -i 's|DEP_JARS =../../java/dist/rasj.jar|DEP_JARS =../../java/target/rasj-jar-with-dependencies.jar|g' /home/rasdaman/install/applications/RRasdaman/Makefile.am
RUN sed -i 's|$(CP) $(DEP_JARS)  $(RJAVADIR)|$(CP) $(DEP_JARS)  $(LIBS)|g' /home/rasdaman/install/applications/RRasdaman/Makefile.am
RUN sed -i 's| java/README||g' /home/rasdaman/install/applications/RRasdaman/Makefile.am
RUN sed -i 's|VERSION=0.9|VERSION=9.2.1|g' /home/rasdaman/install/applications/RRasdaman/Makefile.am

RUN make --directory=applications/RRasdaman/ 
RUN make install --directory=applications/RRasdaman/



RUN mkdir $RASDATA && chown rasdaman $RASDATA 


# Some neccessary rasdaman adjustments
RUN sed -i 's/=petauser/=rasdaman/g' $RMANHOME/etc/petascope.properties
RUN sed -i 's/=petapasswd/=rasdaman/g' $RMANHOME/etc/petascope.properties
RUN sed -i 's!petascope.log!/tmp/petascope.log!' $RMANHOME/etc/log4j.properties
RUN sed -i 's!/home/rasdaman/install!$RMANHOME!' $RMANHOME/bin/update_petascopedb.sh



# Adjust PostgreSQL configuration
RUN echo "host all  all    127.0.0.1/32   trust" >> /etc/postgresql/9.5/main/pg_hba.conf
#RUN echo "host all  all    0.0.0.0/0   trust" >> /etc/postgresql/9.1/main/pg_hba.conf # only for debugging!!!
RUN echo "local all  all      peer" >> /etc/postgresql/9.5/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.5/main/postgresql.conf # should be replaced with localhost in production
RUN /etc/init.d/postgresql start \
	&& su - postgres -c"psql -c\"CREATE ROLE rasdaman SUPERUSER LOGIN CREATEROLE CREATEDB UNENCRYPTED PASSWORD 'rasdaman';\"" \
	&& su - rasdaman -c"$RMANHOME/bin/create_db.sh" && su - rasdaman -c"$RMANHOME/bin/update_petascopedb.sh"





# Add persistent environment variables to container 
RUN echo "export RMANHOME=$RMANHOME" >> /etc/profile \
	&& echo "export CATALINA_HOME=$CATALINA_HOME" >> /etc/profile \
	&& echo "export PATH=\$PATH:$RMANHOME/bin" >> /etc/profile \
	&& echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile 


	
	
# SETUP RASGEO EXTENSTION # 

RUN mkdir /home/rasdaman/.rasdaman 
COPY ./rasconnect /home/rasdaman/.rasdaman/


# COPY SOME UTILITIES AND DEMONSTRATIONS
COPY ./demo.sh /home/rasdaman/
RUN chmod 0777 /home/rasdaman/demo.sh
COPY ./container_startup.sh /opt/
RUN chmod 0777 /opt/container_startup.sh
COPY ./rasmgr.conf $RMANHOME/etc/
COPY ./supervisord.conf /etc/supervisor/conf.d/
COPY ./pgconfig.sh  /home/rasdaman/pgconfig.sh
RUN chmod 0777 /home/rasdaman/pgconfig.sh
COPY examples /home/rasdaman/examples
RUN find /home/rasdaman/examples -type d -exec chmod 0777 {} + && find /home/rasdaman/examples -type f -name "*.sh" -exec chmod 0777 {} + # Make all example scripts executable

RUN mkdir $R_LIBS

RUN chown -R rasdaman $RMANHOME
RUN chown -R rasdaman /home/rasdaman
RUN mkdir /opt/shared /opt/modisdata # TODO: Add environment variable for shared folder
RUN chmod -R 0777 /opt/shared /opt/modisdata # Allow all users writing to shared folder # This does not work yet, maybe rights for volumes are reset during docker run?

EXPOSE 7001 8080 22 5432 8787

CMD ["/usr/bin/supervisord"]
