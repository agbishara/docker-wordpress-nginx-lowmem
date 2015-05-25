# docker-wordpress-nginx-lowmem

This docker image is aimed to provide secure and robust wordpress configuration by providing
a Dockerfile that installs latest:
 * MySQL
   * with optional LOW MEMORY configuration - perfect for your 512 MB VPS instance
 * Wordpress with:
   * W3 Total Cache plugin - In case you want to use it, for example for Object Cache (page cache handled already by nginx)
 * Nginx with
   * FastCGI Page Cache with purging capabilities via nginx helper wordpress plugin and nginx fastcgi_cache_purge module
   * Preconfigured [http_realip_module](http://nginx.org/en/docs/http/ngx_http_realip_module.html) with [CloudFlare ip addresses](https://www.cloudflare.com/ips)
   * Auto generated self-signed SSL certificates with [modern](https://mozilla.github.io/server-side-tls/ssl-config-generator/?1) cipher suite including elliptic curve for [perfect forward secrecy](http://cryptography.wikia.com/wiki/Perfect_forward_secrecy)
   * fastcgi_cache_use_stale - high availability configuration - ensures to serve content from the cache in case your PHP backend is not available
   * X-Fastcgi-Cache - header indicating cache hit
 * php-fpm + php-apc

### Credits:
 This code is baed on work by:
 * [eugeneware](https://github.com/eugeneware/docker-wordpress-nginx)
 * [jbfink](https://github.com/jbfink/docker-wordpress) who did most of the hard work on the wordpress parts! You can check out his [Apache version here](https://github.com/jbfink/docker-wordpress).
 * http://rtcamp.com/ - for providing nginx repo with fastcgi_cache_purge module

## Installation

The easiest way to get this docker image installed is to pull the latest version
from the Docker registry:

```bash
$ sudo docker pull fluential/docker-wordpress-nginx-lowmem
```

I highly recommend you build this image yourself, never trust anything you get from the internet:

```bash
$ git clone https://github.com/fluential/docker-wordpress-nginx-lowmem
$ cd docker-wordpress-nginx-lowmem
$ sudo docker build -t="fluential/docker-wordpress-nginx-lowmem" .
```

## Recommended Usage
I highly recommend creating an initial container with data volumes, this will make further workflows with --volumes-from much easier.
When you play a lot with containers things can get messy pretty quickly, you then go and start deleting unused / stopped containers - very often its the case that you actually delete your actual container which leaves behind orphaned volumes where your important data is stored.

By creating a single container with data volumes most likely you will never get to delete it and you can always use --volumes-from to play with configuration

```bash
$ sudo docker create --name wp-data fluential/docker-wordpress-nginx
```

You need to make sure that ports you want to use are are actually available:

```bash
$ sudo netstat -lnp|grep ":443"
$ sudo netstat -lnp|grep ":80"
```

If above commands do not produce any output that means you are good to go.
To spawn a new instance of wordpress on port 80, SSL on port 443 and LOW MEMORY MySQL config run:

```bash
$ sudo docker run -p 80:80 -p 443:443 -e LOW_MEM=yes --name wp4 -d fluential/docker-wordpress-nginx-lowmem
```

Many times you actually run multiple containers and you do not want to expose container services directly, you then make them available on another ports, use iptables or another proxy to pass traffic.
If you want to bind to different ports, 8000 and 8443 respecitvely:

```bash
$ sudo docker run --volumes-from wp-data -p 8000:80 -p 8443:443 -e LOW_MEM=yes --name docker-wordpress-nginx-lowmem -d fluential/docker-wordpress-nginx
```

When first starting your container, it may take some time for Diffie-Hellman file to be generated, be patient, you will see openssl process taking significant amount of CPU.
After running your container, inspect your logs:
```
```bash
$ sudo docker logs docker-wordpress-nginx-lowmem
```

You should be able to verify that MySQL LOW MEMORY config is enabled:

```bash
$ docker logs docker-wordpress-nginx-lowmem 2>&1|grep -i LOW
[2015-05-24T13:46:54+0000]: LOW MEMORY mysql enabled!
```

#### Volumes
Keep it mind that this docker image exposes following volumes: ```VOLUME ["/var/lib/mysql", "/usr/share/nginx/www", "/var/log/", "/etc/nginx/"]```

You can actually log into a container and modify your config files, the change will be persistent.
That also means, when you want to run another continer WITHOUT low memory mysql configuration you need to enter the container itself and move config file to its original place:

```bash
$ sudo docker exec -ti docker-wordpress-nginx-lowmem bash
$ mv /etc/mysql/conf.d/mysql-low-mem.cnf /etc/mysql/conf.d/mysql-low-mem.cnf.disabled
```

To access mysql, do:

```bash
$ sudo docker exec -ti docker-wordpress-nginx-lowmem mysql
```

#### SSL certificates
This image generates self signed certificates which are not trusted therefore you wil have to accept security warning in your browser.
Nginx comes preconfigured with [modern](https://mozilla.github.io/server-side-tls/ssl-config-generator/?1) secure cipher suite including elliptic curve for [perfect forward secrecy](http://cryptography.wikia.com/wiki/Perfect_forward_secrecy).
It is a good practice to use SSL to encrypt traffic whenever you are logging into your wordpress instance, otherwise your admin password can easily be intercepted.

There are two options you can use when starting a container:
  * -e SSL_KEYSIZE - specifies SSL RSA key length (default: 2048)
  * -e DH_KEYSIZE  - set Diffie-Hellman key length (default: 1024)

It is recommended to increase those values via custom run command, this will ensure high grade encryption which is considered secure for today standards:

```bash
$ sudo docker run --volumes-from wp-data -p 8000:80 -p 8443:443 -e LOW_MEM=yes -e SSL_KEYSIZE=4096 -e DH_KEYSIZE=2048 --name docker-wordpress-nginx-lowmem -d fluential/docker-wordpress-nginx
```

If you want to replace auto generated certificates with your custom ones, just replace single file and restart nginx:

```bash
$ sudo docker exec -ti docker-wordpress-nginx-lowmem bash
$ vim /etc/nginx/conf.d/sslbundle.pem
$ supervisorctl restart nginx
```

### Running
After starting docker-wordpress-nginx-lowmem, check it is running and the port mapping is correct.  This will also report the port mapping between the docker container and the host machine.

```
$ sudo docker ps

0.0.0.0:8000->80/tcp, 0.0.0.0:8443->443/tcp
```

You can the visit the following URL in a browser on your host machine to get started, (pay attention to use the ports you started container with)

```
http://127.0.0.1:80
or
https://127.0.0.1:443 - accept security warning that comes from self signed certificates
```

#### Caching
This docker image will create a setup that heavily relays on nginx FastCGI Cache with purging capabilities via nginx helper wordpress plugin and nginx fastcgi_cache_purge module.
Most of the times this type of Page Cache is better than anything provided by wordpress plugins, the reason for that is simple - any wordpress pluging has to be executed by PHP which is much more time and resource consuming than handling everything on nginx layer.

Since most of the time you are running this image on a tiny 512 MB VPS instance, we want to avoid PHP execution because it eats up precious memory and cpu cycles.
By default we cache everything that could be considered content and avoid caching everything that is considered a part of a wordpress active application - wp-admin panel for example.
It may be the case that you are having loads of editors or there is intense usage of wp-admin section - in this particular small case you may consider enablind w3 total cache plugin with Object Cache which could potentially improve your experience.
Most of the time Nginx internal fastcgi cachce should be good enough - please remember to configure auto purging in Nginx Helper pluging.

Nginx sets browser cache headers for static content to be 7 days, I think that's good enough I don't personally like the maximum value there which potentially could cause issues.
