+++
title = "Symfony finally swiped right on envvars (the gifless edition)"
date = 2017-09-26 18:38:00+10:00
+++

##### _(Or, “why do we keep baking secrets into our artifacts?”)_

A paper on the talk I gave at the [Melbourne Symfony Developers group](https://www.meetup.com/Melbourne-Symfony/) on September 26, 2017. Slides are available [here](https://www.slideshare.net/SamJarrett4/symfony-finally-swiped-right-on-envvars).

<!-- more -->

![Back to the Future](back-to-the-future.gif)

## Symfony is unique as a web framework. 

### Most frameworks and applications re-read configuration with each boot. 

* Booting in the the sense of refers to the app loading on each page load.
* In comparison, Symfony demands that you compile the application entirely before you boot it.
* Not just something that occurs in PHP. Ruby, Python, Node, etc all do this. 
Java also suffers from this same issue, but you notice it differently...

### `$ bin/elasticsearch`
… wait 30 seconds
`$ curl localhost:9200`
[timeout]
… wait 30 more seconds…
`$ curl localhost:9200`
[timeout]
… wait 30 more seconds…

* This is familiar with any time you’ve ever booted a java app. Building the configuration tree and configuring the services is mostly why they take so long to start accepting traffic!

### Symfony compiles the DI container to PHP, including all configuration values.

* Which gives us a good speed improvement because the app doesn’t have to load all of it’s configuration and build the container at runtime! 
* This creates a big problem when we have complex build and deploy processes that need to operate at scale (how do you deploy to 20+ instances quickly? prebuild!) and still protect secret values
* Modern deployment practices emphasise keeping the artifact static between environments, to be able to more easily replicate issues back in development or testing environments.
* Container compilation means that we can’t guarantee that our artifact compiles correctly or that it is exactly the same in production. So, how do we solve this in Symfony? 

## But first… Let’s talk about secrets.  

### What is a secret?

* Secrets can be any form of data that you wouldn’t want to be widely spread around. 
* Database credentials
* SMTP logins
* SMS or EDM api keys
* Payment gateway keys
* AWS credentials (access keys, etc)

### The modern app has so many!

* Some more obscure things include:
* S3 bucket names
* SSH or deploy keys
* JWT keys or certificates
* Internal hostnames (i.e. unprotected internal systems you’re hiding): redis, memcached, finance systems, etc
Lead developer’s email address (for emailing emerging issues, I guess)
* Pagerduty/OpsGenie alert topics/email address (don’t want these abused overnight waking up on call staff!)
* Slack tokens
* … _Service n_’s API key

Summary: An application secret is anything you wouldn’t be comfortable putting directly in the HTML markup itself.

## Here’s why we get a bad rep as PHP developers

Here are some ways I’ve seen secret management in production apps. Let’s take a look back through some ways PHP apps have managed secrets before the current generation.

### The know it all “pattern”

* Create a single class or factory class, and delegate responsibility for it to provide you with answers, 
* Ultimately embedding the secret for all environments in it -- e.g. 

      const LIVE_DATABASE_STRING = 'mysql://root:root@localhost:3306/prod';
      const TEST_DATABASE_STRING = 'mysql://root:root@localhost:3306/test';

* Compromise here on either test or production means all of your secrets are gone.

### The build it & they’ll come “pattern”

* Use ini, json, yaml, java.properties style or some other configuration format to specify all of your values
* Create a php-class as a template full of placeholders that a template parser can quickly generate the final value for you -- e.g.

      const DATABASE_STRING = '{{ database_string }}';

* Generate the PHP from the template before deploying (as part of a build or deploy process)
* Include the final configuration (without the config file) as part of your deployment artifact.
* ???
* Profit?

> ### My biggest professional fuck-up, probably?
> Dropping a production database because a test-site was misconfigured to use it by one of the above secret management methods _(you can guess)_

### The config.yml is the new Config class …. “pattern”

* Same management principal as the config class (“know it all”), but instead we add some Symfony flair!
* Use `config_dev.yml` and `config_prod.yml` to store secrets for each environment
* Largely seen in remnants of old Symfony 2.0 projects, from before the framework suggested a way of swapping values out yet (i.e. pre-`parameters.ini` & `.gitignore` recommendations)

## Into today

(As is common in many Symfony projects)

### The Fabien told me to “pattern”

* Define your config keys in a file called parameters.yml.dist, setting sane (development?) values
* Store actual configuration in S3, build servers, CI or wherever you build your app
* At build-time, copy the file into app/config & build the container (cache-warm / cache-clear)
* Best of the bad approach
* Because of Symfony’s cache compilation, it makes this insecure and difficult to update

### What’s wrong with this approach?

* How secure is your CI? 
  * CI systems can be hacked. 
  * Does yours have a security breach notification policy?
* Who has access to wherever the parameter values are stored?
  * If it’s in S3 or on a server somewhere that the CI can access, can others?
  * Do you audit access to this?
* Rolling any keys mean rebuilding and redeploying the entire application
  * In the midst of a security incident, this may allow an unacceptable delay to roll a pivotal secret, or mean that your application “goes down” or has degraded functionality until the build/deploy completes
  * If the key is something critical (e.g. database), you can’t do a rolling deploy - it has to be all or nothing.
* Secrets are compiled into the container class!
  Try it yourself:
  
      $ grep “database.host” var/cache/prod/*.php
  Pro-tip: If you ever lose them, you can look at `var/cache/prod/appProdContainer.php` in any previous deploy for your DB creds!
* Creating new deployments is hard!
  * Want to add a pre-prod? 
  * Or test a new feature on prod-like infra? 
  * New deployments now involve: updating your CI & build process, building a new artifact, updating your deployment process & tools
* Production artifact differs to test
  * How sure are you that the issue doesn’t exist solely on production?
  * Can developers 'drag' the exact artifact down to their machine to replicate?

## OK, so what’s the answer?

### Introducing environment variables (“envvars”) - the good

* Easy to set up in your app
* Functions mostly just like another parameter
* Not compiled into the container (although defaults are)
* Like other parameters, still allows default values to be set
* Updating values is easy! Just update wherever the value is stored and reload PHP

### Introducing environment variables (“envvars”) - the not so good

* Can’t (currently) access the value outside of a service, e.g. in a controller, so implementing may mean refactoring the application
* Can be difficult to use environment variables consistently if you run your application outside of Docker
* Some libraries don’t _quite_ support envvars yet

## Porting an existing application is easy

* Drop any periods (“`.`”) in parameter names and replace with underscores
  e.g. `database.host` becomes `database_host`, or better yet, `DATABASE_HOST` (although Symfony doesn't care)
* Wrap the parameter name with “`env()`”
  e.g. `database.host` becomes `env(DATABASE_HOST)`
* Wherever the variable is used (`services.yml`, `config.yml`, etc), replace the key the same way
* If any don’t support environment variables, you can sometimes replace with what Symfony calls a _dynamic_ parameter
  * Dynamic parameters are mostly used whenever you have a parameter that refers to another parameter
  * The container delays calculating the value until as late as possible, so the full value only gets cached when it’s first used
  * To do it, update your parameters as above, but also define a parameter like so:
    `old.parameter.name: %env(PARAMETER_NAME)%`
  * Can be used if you must access the parameter in a controller or other non-service space
  * but probably suggests you need to refactor
  * Does not work if a library needs the value at container compilation time (e.g. if a container extension needs it to decide what class to use based on a value)

### While you’re porting

* In Symfony we think of application environments (dev, test and prod only, usually), and try to keep agnostic to deployment environments (e.g. test/staging server is still running the production application environment)
* But it’s valuable to consider what values actually change between deployment environments
* Consider using application-deployment environments - i.e. the combination of what mode the application runs in *and* what deployment you're running in
* Anything that doesn’t change between app or deployment environments that isn't sensitive/secret should go into `config.yml` as a `parameters:` block (see [Symfony standard edition recommendation](https://github.com/symfony/symfony-standard/blob/3.3/app/config/config.yml#L6-L9))
* Anything that changes between application environments but not deployemnts (that isn't sensitive/secret) should be stored in `config_dev.yml` or `config_prod.yml` as a `parameters:` block
* Anything that changes between deployments or is secretive is a good candidate to live in the environment

### Any gotchas?

* You need to defer making decisions on anything that changes per-deployment until later. -- e.g. any decisions made in a container extension
* Dynamic parameters don’t solve this (`%param% => %env(PARAM)%`)
* If it’s your bundle/extension, you can try using another mechanism, such as factory services to work around this

### The Dotenv component in Symfony 3.3

* Solves the biggest challenge using env vars: development environments where setting envvars is traditionally difficult
* Symfony flex uses it out of the box!
* It’s a small class that is added in your `app`/`app_dev.php` and `console` scripts
* Provides env-var like support in places you can’t easily set variables (development!)
* In Flex, it serves to replace the parameters.yml paradigm
* Relatively easy to back-port into the full-stack framework

## Or...

### You can use Docker in development! 

Docker is now quite stable on Mac and Windows!

* Mac: https://www.docker.com/docker-mac
* Windows: https://www.docker.com/docker-windows

## It’s not (all) about security

I've talked a bit about how this is really all about security, but there's one big gotcha:

![Fabien Potencier's note about environment variables](fabien-on-environment-vars.png)

![Note about environment variables not providing any security](environment-vars-provide-no-extra-security.png)

### Environment variables are not perfect

* Doesn’t solve security out of the box for anyone with access to your servers
* Can be accessed outside your application - e.g. any `shell_exec()` calls you make get the full environment
* Anything run as the Apache, PHP or www-data user, or someone sudo-ed to it can unintentionally expose to another program
* Any insecure libraries in your application can access the values, too
* Can unintentionally end up in logs or the Symfony profiler, so be careful with what you log your app!
* Your plain text values are likely to be stored somewhere, too (some ideas on this below)

### How do I make this better?

* Current PR: [github/symfony/symfony#23901](https://github.com/symfony/symfony/pull/23901) (due Symfony 3.4) adds features to support docker/kubernetes secrets out of the box & make this extendable in your app!
* Once it’s available to us, here’s some ideas on how you can keep your raw values safe...
* If you use AWS for your application, possibly: 
  * KMS-encrypted value provided as an environment variable and a provider that decrypts at run-time
  * Using SSM Parameter Store to fetch values at run-time
  * You can use both of these services without running locally on AWS, but integration with short-lived machine tokens so you don't need to embed an access key & secret in the machine somewhere makes it much more appealing
* Not on AWS? [Google Cloud KMS](https://cloud.google.com/kms/docs/secret-management) for their equivalent to KMS might offer a similar idea
* Or you can use other open-source tools and write custom providers to fetch & decrypt (hopefully the community helps here!) - existing secret management tools like:
  * [Hashicorp Vault](https://www.vaultproject.io/)
  * [Pinterest Knox](https://github.com/pinterest/knox)
  * [Lyft Confidant](https://lyft.github.io/confidant/)
* In the meantime, before we can use 3.4: if you’re hosting on AWS, use [KMS-encrypted](https://aws.amazon.com/kms/) environment variables or fetch from SSM Param. Store at container boot (open-source tools exist to help with this!)

### Further reading

* Were any of the ideas on using the environment a surprise? PHP developers have shied away from it until recently, while other languages have embraced them entirely for config. Check out the [12 factor app](https://12factor.net/) for more info.
* [Segment have a great post on managing secrets with AWS SSM parameter store on their blog](https://segment.com/blog/the-right-way-to-manage-secrets/)
* Pre-3.4, if you use KMS-encrypted envvars (encrypted strings): REA’s [Shush](https://github.com/realestate-com-au/shush/) library is a tiny go library to help decrypt your secrets transparently
  Usage is simple - change your execution like so:

      $ shush exec -- php-fpm

* More pre-3.4: If you use SSM parameter store (which provides central management of secrets): Segment’s [Chamber](https://github.com/segmentio/chamber) can help in a very similar way. 
* Taking inspiration from [kubernetes](https://kubernetes.io/docs/concepts/configuration/secret/), Docker swarm mode now has [secrets built-in](https://docs.docker.com/engine/swarm/secrets/).
* Not using Docker? It can be [quite complicated to set](https://ypereirareis.github.io/blog/2015/12/13/symfony-nginx-environment-variables-php-fpm/) env across multiple users + daemons. [Apache](https://httpd.apache.org/docs/2.4/env.html), and [CLI users](https://wiki.archlinux.org/index.php/environment_variables#Globally) share a syntax, but of course [PHP-FPM](https://medium.com/@tomahock/passing-system-environment-variables-to-php-fpm-when-using-nginx-a70045370fad) is different (eye roll).
* For the adventurous: I've got an example of porting a Symfony application to Docker on [Github](https://github.com/samjarrett/Symfony-docker-example) that talks through the changes you would make, commit by commit
