import os
import click
import tempfile

from update import parse_config, get_release_information, get_current_version, get_download_url, download_file, kill_process, extract_file, parse_version

default_config_path = os.path.join(
    os.environ["USERPROFILE"],
    "clash_update.conf"
)


@click.group(help="Update clash for windows")
def cli():
    pass


@click.command(help="Update clash for windows")
@click.option("--config", "-c", show_default=True, required=False, default=default_config_path, help="update with given configuration")
def update(config):
    config = parse_config(config)
    proxy = config.get("proxy", None)
    if config.get("proxy", None):
        click.echo(f"Using proxy: {proxy}")
    else:
        click.echo("Update without proxy")
    res = get_release_information(config["url"], proxy)
    click.echo(f"Latest version: {res['tag_name']}")
    cur_ver = get_current_version(config["path"])
    click.echo(f"Current version: {cur_ver}")

    if parse_version(cur_ver) >= parse_version(res["tag_name"]):
        click.echo("Up to date.")
        return

    download_url = get_download_url(res["assets"], config["pattern"])
    click.echo(download_url)

    archive_name = None
    f = open(os.path.join(os.path.dirname(config["path"]), "clash.for.windows.7z"), "wb")
    archive_name = f.name
    click.echo("Start downloading file...")
    download_file(f, download_url, proxy)
    click.echo("Killing running process...")
    kill_process(config["path"])
    f.close()

    click.echo("Extracting zip file...")
    extract_file(archive_name, config["unzip"], os.path.dirname(config["path"]))


@click.command(help="List, set or remove configurations")
@click.option("list_conf", "--list", is_flag=True, required=False, help="list all")
@click.option("set_conf", "--set", required=False, metavar="<key>=<value>", help="add a new variable")
@click.option("remove_conf", "--remove", required=False, metavar="<key>", help="remove a variable")
def config(list_conf, set_conf, remove_conf):
    click.echo(list_conf)
    click.echo(set_conf)
    click.echo(remove_conf)


cli.add_command(update)
cli.add_command(config)


if __name__ == "__main__":
    cli()
