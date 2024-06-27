# Specify the base image -- SCOPE has been tested on CentOS 6.10 and 7 ---- so Centos
FROM debian:buster AS builder

#Set the working directory to be used when the docker gets run
WORKDIR /usr/

#install needed dependencies
RUN set -ex;                                                                      \
    apt-get update -y;                                                               \
    apt-get install -y g++ cmake make 

# copy the SCOPE source code to the docker image 
COPY SCOPE/ /usr/SCOPE/

# compile the SCOPE source code
RUN set -ex;                                                                      \
    cd /usr/SCOPE;                                                                \
    mkdir build;                                                                  \
    cd build;                                                                     \
    cmake ..;                                                                     \
    make

# The second stage will install the runtime dependencies only and copy
# the compiled executables
FROM debian:buster AS runtime

COPY --from=builder /usr/SCOPE/build/scope /usr/local/bin/
#copy examples for testing 
COPY --from=builder /usr/SCOPE/examples/source_files/ /usr/local/examples/

