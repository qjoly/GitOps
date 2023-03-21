
Le module Terraform Libvirt n'est utilisable que via l'URI `qemu:///system` *(Je souhaite résoudre ce problème au plus vite mais j'ai l'impression qu'il manque quelque chose au provider…)*. Si vous souhaitez lancer ce projet via un utilisateur *non-root*, il est impératif de rendre le socket Qemu disponible pour votre utilisateur.


Je vous recommande donc de modifier la configuration de Libvirt `/etc/libvirt/libvirtd.conf` afin que la valeur `unix_sock_group` soit définie à `libvirt`. Créez ensuite le groupe nommé `libvirt` via la commande `addgroup libvirt`. 

Ensuite, ajoutez votre propre utilisateur à ce nouveau groupe `sudo usermod -a -G libvirt $(whoami)`. 


Une fois le service `libvirtd` redémarré, vous pourrez tester l'accès au socket via la commande `virsh -c qemu:///system list`.
