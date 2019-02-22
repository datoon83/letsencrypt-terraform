# Nginx using Lets Encrypt with Nginx on Azure

To run:

* terraform init
* az login
* terraform apply -auto-approve

This uses Terraform to create an Ubuntu Nginx server with SSL enabled for a site.  This use LetsEncrypt to generate the certificate.

I've not split out the variables to a .tf file.

You'll need to add the variables yourself to get this working.  You'll probably add this to a resource group and forward the traffic to an ip internal to your virtual network.  

It's best to remove the ssh network security group rule.

You may need some additional work depending on where your Domain is registered