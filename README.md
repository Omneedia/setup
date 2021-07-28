# Install omneedia platform

## Install standalone

### For a digital ocean droplet (private network on eth1)
`curl -L https://raw.githubusercontent.com/omneedia/setup/master/setup.sh | bash -s -- --dir=/opt/store --network=eth1 --standalone`

## Install datastore

### For a digital ocean droplet
`curl -L https://raw.githubusercontent.com/omneedia/setup/master/setup.sh | bash -s -- --dir=/opt/store --datastore`
