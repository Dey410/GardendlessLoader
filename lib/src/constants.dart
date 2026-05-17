const appDisplayName = 'GardendlessLoader';
const appBundleId = 'io.github.dey410.gardendlessloader';
const githubUrl = 'https://github.com/Gzh0821/pvzge_web';
const appGithubUrl = 'https://github.com/Dey410/GardendlessLoader';
const bilibiliHomeUrl =
    'https://space.bilibili.com/523667580?spm_id_from=333.1007.0.0';
const remoteAnnouncementUrl =
    'https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/announcements.json';
const resourceFolderName = 'GardendlessLoader';
const localServerHost = '127.0.0.1';
const localServerPort = 26410;
const localOrigin = 'http://$localServerHost:$localServerPort';
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
const announcementTimeout = Duration(seconds: 3);
const announcementMaxBytes = 32 * 1024;

const disclaimerText =
    '本 App 不内置 PvZ2 Gardendless 游戏资源。请从项目 GitHub 获取资源并自行导入。\n'
    'PvZ2 Gardendless 及其资源版权、许可证和更新由原项目维护。';
