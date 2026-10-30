const dialog=document.querySelector('#image-preview');
const previewImage=dialog.querySelector('img');
const previewCaption=document.querySelector('#preview-caption');
for(const button of document.querySelectorAll('[data-preview]')){
  button.addEventListener('click',()=>{
    previewImage.src=button.dataset.preview;
    previewImage.alt=button.dataset.caption;
    previewCaption.textContent=button.dataset.caption;
    dialog.showModal();dialog.scrollTop=0;
  });
}
dialog.querySelector('.preview-close').addEventListener('click',()=>dialog.close());
dialog.addEventListener('click',event=>{
  if(event.target!==dialog)return;
  const r=dialog.getBoundingClientRect();
  if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();
});
const views={
  columns:{image:'assets/octo-document-preview.jpg',alt:'分栏视图，在目录旁预览文档和图片',caption:'沿层级浏览，右侧直接查看文档和图片；文件夹或空白处右键即可新建文件。'},
  list:{image:'assets/octo-list.jpg',alt:'Octo 列表视图，显示文件名称、修改日期和大小',caption:'名称、修改日期、大小，点表头即可排序。列表还支持逐级展开文件夹。'},
  icons:{image:'assets/octo-icons.jpg',alt:'Octo 图标视图，以图标和缩略图浏览文件',caption:'图标和缩略图放在眼前；这张截图使用隔离样例目录导出。'}
};
const tabs=[...document.querySelectorAll('[data-view]')];
const panel=document.querySelector('#view-panel');
const shot=panel.querySelector('[data-preview]');
function selectView(tab){
  const view=views[tab.dataset.view];
  for(const button of tabs){const selected=button===tab;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;}
  panel.setAttribute('aria-labelledby',tab.id);
  const image=document.querySelector('#view-image');image.src=view.image;image.alt=view.alt;
  shot.dataset.preview=view.image;shot.dataset.caption=view.caption;shot.setAttribute('aria-label','放大'+tab.textContent+'视图截图');
  document.querySelector('#view-caption').textContent=view.caption;
}
for(const tab of tabs){
  tab.addEventListener('click',()=>selectView(tab));
  tab.addEventListener('keydown',event=>{
    let index=tabs.indexOf(tab);
    if(event.key==='ArrowRight')index=(index+1)%tabs.length;
    else if(event.key==='ArrowLeft')index=(index+tabs.length-1)%tabs.length;
    else if(event.key==='Home')index=0;
    else if(event.key==='End')index=tabs.length-1;
    else return;
    event.preventDefault();selectView(tabs[index]);tabs[index].focus();
  });
}
