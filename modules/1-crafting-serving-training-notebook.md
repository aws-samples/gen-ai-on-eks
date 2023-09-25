# Experimenting and creating our Serving and Training script

In this first module we are going to open JupyterHub and logging-in to create our user session, let's start by exposing JupyterHub using `kubectl port-forward.`

> **Note:** We are not exposing via LoadBalancer to avoid security risks, since we are using Jupyter dummy auth.

## Accessing JupyterHub

Exposing JupyterHub endpoint:

```bash
kubectl port-forward svc/proxy-public 8080:80 -n jupyterhub
```

> You can choose any port that you'd like (local-port):(service-port)

Since we are using JupyterHub `dummy` auth mechanism, we can define **any user and password** in-order to get access to Jupyter Console:

![ML Ops Arch Diagram](../static/jupyter-login.png)

Select [X] the GPU Server profile in JupyterHub and click in `Start`.

![ML Ops Arch Diagram](../static/server-start.png)

Now wait for the Server to start up.

## Downloading Notebook

We already have developed a Jupyter Notebook with the steps to craft a train and serving script, let's start by openning a `Terminal` window in our Jupyter console and downloading our script from GitHub:

![ML Ops Arch Diagram](../static/terminal-open.png)

Once you have your `Terminal` opened, execute the below script to download the notebook:

<!-- TBD: Change here to URL from aws-samples -->
```bash
wget https://raw.githubusercontent.com/lusoal/fm-ops-eks/main/notebooks/llm_train_serve.ipynb
```

![ML Ops Arch Diagram](../static/terminal-download.png)

Now go back to the previous screen, and open the Notebook:

![ML Ops Arch Diagram](../static/notebook1.png)



