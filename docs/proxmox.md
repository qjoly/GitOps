
# Création d'un utilisateur proxmox

Par sécurité, je vous recommande de créer un utilisateur proxmox avec les permissions minimales.

Vous devrez d'abord créer un utilisateur ayant les permissions nécéssaires à la création/modification d'une machine virtuelle. Lancez les commandes suivantes dans le terminal d'un Proxmox *(un des noeuds du cluster)* :
```bash
export role_proxmox=gitops
export user_proxmox=gitops
pveum role add ${role_proxmox} -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt VM.Console"
pveum user add ${user_proxmox}@pve
pveum aclmod / -user ${user_proxmox}@pve -role ${role_proxmox}
```
*Note: la permission VM.Console est uniquement utilisée par Packer*.

Vous devrez également ajouter les accès à vos pools de stockage manuellement *(Datacenter -> Permissions -> Add)*:

<center>
    <img src="../img/perms-iso.png" >
</center>

Une fois les permissions ajoutées, vous pouvez définir un mot de passe à votre utilisateur directement sur la WebUI
