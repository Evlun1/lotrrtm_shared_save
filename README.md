# LOTR Return to Moria Shared Save project

This is a small personal project to allow sharing a common game save of Return to Moria with friends.

## The use case

We are playing a common game with friends over the internet. One person hosts the game on its computer, and the rest join.
The same game can last up to hundreds of hours, so we decide that we do not need the same team every time : unavailable friends can leave for a day, others can join.

The problem is that the host has the game save, and as such, if the host is not available, we can't launch the game save.

This project allows the host to store the save file remotely (on S3) so that other players can fetch it if needed and become the host of the game in turn.

To prevent multiple unaware people from downloading the same save and launching multiple games at the same time with different players (which would be a catastrophy), there also is a locking mechanism so that once a save is downloaded, it can't be downloaded again until it is updated and made available.

Another option would be to launch a remote server on a cloud virtual machine, but this requires some windows machine setup. Yet another option would be to pay for a permanent server, but it turns out paid solutions are quite a budget, reaching 70€/mon if we want to have a recommended 8GB setup with everything available.

## The technical solution

There are two folders : backend and infra. The whole project relies on AWS to work.

- the backend has a quick FastAPI python project with two routes : one to post the save, and one to fetch it (and lock it for others)
- the infra folder, on Terraform, deploys the backend in a lambda function, creates an S3 to store files, SSM parameters to store lock state and file names, and appropriate IAM role & policy
- the scripts folder, with a bash script utility to automatically call app when launching PC game through Steam to fetch save, and upload it back when game is over

### Security considerations

To provide basic security for the application, you must pass a password value of your choice when creating your infrastructure, at most 20 characters.

This value is then stored as an SSM parameter SecureString in AWS, to be read by application.

Be still warned that this application, even though having minimal IAM rights and an uncomitted password, could not be considered as secured according to production grade standards. 

### Requirements

#### AWS

As the API is currently deployed on AWS (and tailored for S3 and SSM services), you need to have an AWS account available.

You also need to launch terminal with appropriate AWS setup, eg as shown in options [2 or 3 here](https://wellarchitectedlabs.com/common/documentation/aws_credentials/).
A more advanced vault option to consider for seasoned users I can recommend is [aws-vault](https://github.com/99designs/aws-vault).

#### Backend

- python (recommended 3.12)
- a package management tool (at least pip, I can recommend [uv](https://docs.astral.sh/uv/getting-started/installation/)) with commands below
- optional but strongly recommended : a virtualenv tool (uv can work too)
- an AWS account for local tests, as calls to S3 and SSM aren't mocked currently

```bash
# In a terminal
cd backend
# Setup backend
uv venv --python 3.12
uv pip install -r requirements.txt
# Launch backend locally (needs AWS setup in terminal and .env file complete)
uv run main.py
# Should you add new requirements
uv pip freeze > requirements.txt
# Prepare zip dir for lambda packaging for infra (-t option not in uv pip so gotta workaround it)
uv run pip install -r requirements.txt -t zip_build_dir
cp main.py zip_build_dir/
```

#### Infra

- a zip dir with backend code and requirements (see last backend instruction)
- terraform
- and AWS 

```bash
# In a terminal with AWS account setup
cd infra
terraform init
export TF_VAR_ssm_pasword_value=xxxx  # at most 20 chars of your choosing
terraform plan
terraform apply
```

#### Script

Many thanks to @MoaMoaK for providing [the original version of the script](https://gitlab.com/-/snippets/4832002) ! 

If you want to use provided script, you need to have a bash version installed on your computer, and Return To Moria as a Steam game.

1. Copy script to a path of your choice and complete all parameters
2. Open Return To Moria game page in your Steam Library
3. Click on Settings/Properties/General
4. In launch options, set : `bash [your_script_path/lotr_moria_steam_wrapper.sh] "%command%"`
