const appDisplayName = 'GardendlessLoader'; // App 显示名称
const appBundleId =
    'io.github.dey410.gardendlessloader'; // App 包名（Bundle ID），用于区分不同平台的应用
const githubUrl =
    'https://github.com/Gzh0821/pvzge_web'; // GitHub 仓库地址，指向 PvZ2 Gardendless 项目的源代码
const appGithubUrl =
    'https://github.com/Dey410/GardendlessLoader'; // GardendlessLoader 的 GitHub 仓库地址
const gameReleaseNotesUrl =
    'https://github.com/Gzh0821/pvzg_site/releases/tag/{version}'; // 上游游戏版本的更新说明，{version} 替换为版本号
const cloudDriveUrl =
    'https://pan.quark.cn/s/c3da839ca8b1?pwd=qLBU'; // 网盘地址，加载器更新与游戏资源下载默认共用
const bilibiliHomeUrl = 'https://space.bilibili.com/523667580'; // B站主页地址
const remoteAnnouncementUrls = [
  'https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/announcements.json',
  'https://cdn.jsdelivr.net/gh/Dey410/GardendlessLoader@main/announcements.json',
]; // 远程公告 URL，按顺序尝试；GitHub 无法访问时改用 jsDelivr
const remoteAboutContentUrl =
    'https://raw.githubusercontent.com/Dey410/GardendlessLoader/main/about_content.json'; // 远程关于内容 URL
const resourceFolderName = 'GardendlessLoader'; // 资源文件夹名称
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.9.0');
const announcementTimeout = Duration(seconds: 3); //公告请求超时时间
const announcementMaxBytes = 32 * 1024; //公告请求最大响应体大小，32KB应该足够了
const aboutContentTimeout = Duration(seconds: 3); //关于内容请求超时时间
const aboutContentMaxBytes = 16 * 1024; //关于内容请求最大响应体大小
