# Use the Jupyter datascience-notebook base image
FROM jupyter/datascience-notebook

# Switch to root user to install system dependencies
USER root

# Install system dependencies
RUN apt-get update \
    && apt-get install -y graphviz git libpq-dev python3-dev

# Switch back to the jovyan user for Python package installations
USER jovyan

# Clone and install the SPARQL kernel
RUN cd /tmp && git clone https://github.com/asanchez75/sparql-kernel.git \
    && cd /tmp/sparql-kernel && python setup.py install

# Install additional Python packages using pip, it can change depending if using GPU or not
RUN pip3 install graphviz \
    && pip3 install ipython-sql \
    && pip3 install psycopg2 \
    && pip3 install gastrodon \
    && pip3 install tensorflow \ 
    && pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu \ 
    && pip3 install transformers

# Install the SPARQL kernel for Jupyter
RUN jupyter sparqlkernel install --user
