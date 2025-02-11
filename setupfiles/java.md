#JAVA

## jenv

[GitHub - jenv](https://github.com/jenv/jenv)

Run to view all version jenv knows about

```
jenv versions
```

### debug jenv

```
jenv doctor
```

## jenv set version

jenv can set Java versions at 3 levels:

- global (lowest priority)
- local
- shell (highest priority)

```
jenv global 21.0.2
jenv global --unset
```

## Adding Your Java Environment

Use jenv add to inform jenv where your Java environment is located. jenv does not, by itself, install Java.

Use brew to install the latest Java (OpenJDK 21) and symlink into /Library

```
brew install java
sudo ln -sfn /usr/local/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
jenv add "$(/usr/libexec/java_home)" # this will always default to the latest version in /Library/Java/JavaVirtualMachines
# or
# jenv add /Library/Java/JavaVirtualMachines/openjdk.jdk
```

## Install a second JVM

Then say we need JDK 8 for android dev:

```
brew install openjdk@8
sudo ln -sfn /usr/local/opt/openjdk@8/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-8.jdk
```

This will install the latest version of Java 8 to a special directory in macOS. Let's see which directory that is:

```
$ ls -1 /Library/Java/JavaVirtualMachines
openjdk-8.jdk
openjdk.jdk
```

then we add the exact name:

```
$ jenv add /Library/Java/JavaVirtualMachines/openjdk-8.jdk/Contents/Home/
```
