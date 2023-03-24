

# Failed to connect fe80::

En utilisant le provider Libvirt sur Terraform, il est possible que vous tombiez sur cette erreur durant le lancement d'Ansible.
```
│ TASK [Gathering Facts] *********************************************************
│ fatal: [kube-0-tf]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ssh: connect to host fe80::5054:ff:fec2:1c4 port 22: Invalid argument", "unreachable": true}
│ ok: [kube-2-tf]
│ ok: [kube-1-tf]
```

La raison est que Terraform récupère l'adresse IP de la machine **avant qu'elle ne puisse obtenir son adresse IPv4**.

La seule solution trouvée pour le moment est de relancer le Terraform pour qu'il obtienne l'IPv4. Le fichier `inventory.ini` sera recréé.