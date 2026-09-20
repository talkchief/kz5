#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Create generic, reusable Jenkins credentials from a root-only key file.

Run by the owner. Values are read from the file and sent to Jenkins only; ids and
kinds are printed, never a value. Existing ids are left alone (Jenkins credential ids
cannot be renamed; use --replace ID to delete and recreate one).

Key file: "name: value" lines, then a line "#jenkins server" followed by
ip / jenkins_username / jenkins_pass (and optionally ssh_user / ssh_pass).

Mapping (generic names, usable by any project):
  github_pat                         -> github-pat       Username with password (user "git"):
                                                          the Git credential for any GitHub repo
                                        github-pat-text  Secret text: API calls, gh, scripts
  gitlab_token                       -> gitlab-token, gitlab-token-text   (user "oauth2")
  gitlab_frontend_token              -> gitlab-frontend-token-text
  <x>_user_<y> + <x>_pass_<y>        -> <x>-<y>          Username with password
  ssh_user + ssh_pass (Jenkins part) -> jenkins-server-ssh
  anything else                      -> <name>-text      Secret text

  sudo python3 scripts/jenkins-import-credentials.py --key-file /root/key [--dry-run]
       [--only ID[,ID...]] [--replace ID[,ID...]] [--insecure]
"""
import argparse
import base64
import http.cookiejar
import json
import os
import re
import ssl
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request

UP = 'com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl'
ST = 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl'
STORE = '/credentials/store/system/domain/_'


def parse(path):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        raise SystemExit('The key file must be a regular file with mode 0600')
    text = open(path, encoding='utf-8').read()
    if '#jenkins server' not in text:
        raise SystemExit('The key file has no "#jenkins server" section')
    top, jenkins = text.split('#jenkins server', 1)
    fields = lambda part: dict((k.strip(), v.strip()) for k, v in
                               (line.split(':', 1) for line in part.splitlines() if ':' in line and not line.startswith(('-', '#'))))
    return fields(top), fields(jenkins)


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def plan(top, jenkins):
    creds, used = [], set()

    def userpass(cid, user, password, note):
        creds.append({'id': cid, '$class': UP, 'username': user, 'password': password, 'description': note})

    def text(cid, secret, note):
        creds.append({'id': cid, '$class': ST, 'secret': secret, 'description': note})

    if top.get('github_pat'):
        userpass('github-pat', 'git', top['github_pat'], 'GitHub personal access token as a Git credential (any repository the token covers)')
        text('github-pat-text', top['github_pat'], 'GitHub personal access token as secret text (API, gh, scripts)')
        used.add('github_pat')
    if top.get('gitlab_token'):
        userpass('gitlab-token', 'oauth2', top['gitlab_token'], 'GitLab access token as a Git credential')
        text('gitlab-token-text', top['gitlab_token'], 'GitLab access token as secret text')
        used.add('gitlab_token')
    for name in sorted(top):
        match = re.match(r'^(.+?)_user(_.+)?$', name)
        if match and (match.group(1) + '_pass' + (match.group(2) or '')) in top:
            partner = match.group(1) + '_pass' + (match.group(2) or '')
            userpass(slug(match.group(1) + (match.group(2) or '')), top[name], top[partner], 'User and password "%s" from the key file' % slug(match.group(1)))
            used.update((name, partner))
    for name in sorted(top):
        if name not in used and top[name]:
            text(slug(name) + '-text', top[name], 'Value "%s" from the key file' % name)
    if jenkins.get('ssh_user') and jenkins.get('ssh_pass'):
        userpass('jenkins-server-ssh', jenkins['ssh_user'], jenkins['ssh_pass'], 'SSH login of the Jenkins server itself')
    return creds


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--key-file', required=True)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--only', default='')
    parser.add_argument('--replace', default='')
    parser.add_argument('--insecure', action='store_true', help='accept a self-signed Jenkins certificate')
    args = parser.parse_args()
    top, jenkins = parse(args.key_file)
    wanted = [c for c in plan(top, jenkins) if not args.only or c['id'] in args.only.split(',')]
    replace = set(filter(None, args.replace.split(',')))
    if args.dry_run:
        for cred in wanted:
            print('%-28s %s' % (cred['id'], 'Username with password' if cred['$class'] == UP else 'Secret text'))
        return 0
    base = 'https://' + jenkins['ip']
    context = ssl._create_unverified_context() if args.insecure else ssl.create_default_context()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
                                         urllib.request.HTTPSHandler(context=context))
    token = base64.b64encode(('%s:%s' % (jenkins['jenkins_username'], jenkins['jenkins_pass'])).encode()).decode()
    opener.addheaders = [('Authorization', 'Basic ' + token)]
    crumb = json.load(opener.open(base + '/crumbIssuer/api/json', timeout=20))
    headers = {crumb['crumbRequestField']: crumb['crumb'], 'Content-Type': 'application/x-www-form-urlencoded'}

    def post(path, data=b''):
        try:
            return opener.open(urllib.request.Request(base + path, data=data, headers=headers, method='POST'), timeout=30).status
        except urllib.error.HTTPError as error:
            return error.code
    existing = {c['id'] for c in json.load(opener.open(base + STORE + '/api/json?tree=credentials[id]', timeout=20))['credentials']}
    for cred in wanted:
        if cred['id'] in existing and cred['id'] in replace:
            post(STORE + '/credential/' + urllib.parse.quote(cred['id']) + '/doDelete')
            existing.discard(cred['id'])
        if cred['id'] in existing:
            print('%-28s exists, left alone' % cred['id'])
            continue
        body = urllib.parse.urlencode({'json': json.dumps({'': '0', 'credentials': dict(cred, scope='GLOBAL')})}).encode()
        print('%-28s HTTP %s' % (cred['id'], post(STORE + '/createCredentials', body)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
