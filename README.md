# conventi

To build the docker imnage use:

```
docker build -t conventi:latest -f pkg/Dockerfile .
```

To initialize a git repositiory for version management and changelog generation use:

```
docker run -v "$(pwd):/conventi" conventi:latest init
```

For updating the version and changelog simply run:
```
docker run -v "$(pwd):/conventi" conventi:latest
```