# Description

This custom puppet function can come in handy if you have your own Docker repo with limited hard drive space available. It does the following things:

  * checks what kind of repos, images and labels are in use by requesting the docker registry
  * if a repo, an image or a label is not present in the yaml data, the image is marked to be removed via DELETE request on the docker registry
    * make sure that in your docker registry config the DELETE method is enabled

# Garbage collection

To actually do the garbage collecting, you have to call `registry garbage-collect` so that the marked images are actually deleted. You can do this by using a cron job for example.

# Parameters

The following parameters are needed:

  * registry_hostname
  * registry_username
  * registry_password
  * data
    * yaml data (refer to example.yaml)

# Example

## Example yaml data

docker_images::data:
  debian:
    image_tags:
      - '11'
      - '12'

## Example function call
The function is called in the following way in your Puppet manifest:

sync_docker_images($registry_hostname, $registry_username, $registry_password, $data)
