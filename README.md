# devop-eval-cluster

A GKE cluster terraform definition, used to set up an evaluation for devops candidates.

It sets up a simple GKE cluster with a gateway, that can be used to expose public services.
It also defines a cloud sql postgres database, that can be used by these services.