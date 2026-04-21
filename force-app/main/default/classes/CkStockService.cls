public without sharing class CkStockService {
    
    @InvocableMethod(label='Decrement Stock' description='Decrements stock for all items in a paid order')
    public static void decrementStock(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;
        
        List<OrderItem> items = [
            SELECT Product2Id, Quantity FROM OrderItem WHERE OrderId IN :orderIds
        ];
        
        if (items.isEmpty()) return;
        
        Set<Id> productIds = new Set<Id>();
        Map<Id, Decimal> qtyMap = new Map<Id, Decimal>();
        
        for (OrderItem oi : items) {
            productIds.add(oi.Product2Id);
            Decimal current = qtyMap.containsKey(oi.Product2Id) ? qtyMap.get(oi.Product2Id) : 0;
            qtyMap.put(oi.Product2Id, current + oi.Quantity);
        }
        
        List<Product2> products = [
            SELECT Id, Stock_Quantity__c, Low_Stock_Threshold__c, Name, Image_URL__c
            FROM Product2 WHERE Id IN :productIds
        ];
        
        List<Product2> toUpdate = new List<Product2>();
        List<Product2> lowStockProducts = new List<Product2>();
        List<Product2> outOfStockProducts = new List<Product2>();
        
        for (Product2 p : products) {
            Decimal ordered = qtyMap.containsKey(p.Id) ? qtyMap.get(p.Id) : 0;
            Decimal newStock = (p.Stock_Quantity__c != null ? p.Stock_Quantity__c : 0) - ordered;
            if (newStock < 0) newStock = 0;
            
            p.Stock_Quantity__c = newStock;
            toUpdate.add(p);
            
            Decimal threshold = p.Low_Stock_Threshold__c != null ? p.Low_Stock_Threshold__c : 10;
            if (newStock == 0) outOfStockProducts.add(p);
            else if (newStock <= threshold) lowStockProducts.add(p);
        }
        
        if (!toUpdate.isEmpty()) update toUpdate;
        if (!lowStockProducts.isEmpty() || !outOfStockProducts.isEmpty()) {
            sendStockAlerts(lowStockProducts, outOfStockProducts);
        }
    }
    
    @AuraEnabled
    public static StockInfo checkStock(String productId) {
        try {
            Product2 p = [
                SELECT Id, Stock_Quantity__c, Availability__c
                FROM Product2 WHERE Id = :productId LIMIT 1
            ];
            
            StockInfo info = new StockInfo();
            info.productId = p.Id;
            info.stockQuantity = p.Stock_Quantity__c != null ? p.Stock_Quantity__c.intValue() : 0;
            
            if (String.isNotBlank(p.Availability__c)) {
                info.availability = p.Availability__c;
                info.canAddToCart = p.Availability__c == 'Sur commande 48h';
            } else if (info.stockQuantity > 0) {
                info.availability = 'En stock';
                info.canAddToCart = true;
            } else {
                info.availability = 'Epuise';
                info.canAddToCart = false;
            }
            
            return info;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }
    
    private static void sendStockAlerts(List<Product2> lowStock, List<Product2> outOfStock) {
        
        // ── Plain text fallback ───────────────────────────────────
        String plainBody = 'Stock Alert - TalFlow Express\n\n';
        if (!outOfStock.isEmpty()) {
            plainBody += '=== RUPTURE DE STOCK ===\n';
            for (Product2 p : outOfStock) {
                plainBody += '- ' + p.Name + ' : 0 unites restantes\n';
            }
            plainBody += '\n';
        }
        if (!lowStock.isEmpty()) {
            plainBody += '=== STOCK BAS ===\n';
            for (Product2 p : lowStock) {
                plainBody += '- ' + p.Name + ' : '
                    + p.Stock_Quantity__c.intValue()
                    + ' unites restantes (seuil: '
                    + p.Low_Stock_Threshold__c.intValue() + ')\n';
            }
        }
        plainBody += '\nConnectez-vous a Salesforce pour reapprovisionner ces produits.';
        
        // ── HTML dynamique ────────────────────────────────────────
        String outOfStockRows = '';
        for (Product2 p : outOfStock) {
            outOfStockRows += '<tr>'
                + '<td style="padding:10px 12px;border-bottom:1px solid #F5C6CB;">'
                + '<span style="color:#E24B4A;font-weight:bold;">🔴</span>&nbsp;'
                + '<strong style="color:#0A1628;">' + p.Name + '</strong>'
                + '</td>'
                + '<td align="right" style="padding:10px 12px;border-bottom:1px solid #F5C6CB;">'
                + '<span style="background:#E24B4A;color:#fff;padding:3px 10px;'
                + 'border-radius:999px;font-size:11px;font-weight:bold;">0 units</span>'
                + '</td>'
                + '</tr>';
        }
        
        String lowStockRows = '';
        for (Product2 p : lowStock) {
            lowStockRows += '<tr>'
                + '<td style="padding:10px 12px;border-bottom:1px solid #FFE4D4;">'
                + '<span style="color:#FF6B1A;font-weight:bold;">⚠️</span>&nbsp;'
                + '<strong style="color:#0A1628;">' + p.Name + '</strong>'
                + '</td>'
                + '<td align="right" style="padding:10px 12px;border-bottom:1px solid #FFE4D4;">'
                + '<span style="background:#FF6B1A;color:#fff;padding:3px 10px;'
                + 'border-radius:999px;font-size:11px;font-weight:bold;">'
                + p.Stock_Quantity__c.intValue() + ' units left</span>'
                + '</td>'
                + '</tr>';
        }
        
        String outOfStockSection = '';
        if (!outOfStock.isEmpty()) {
            outOfStockSection = '<table width="100%" cellpadding="0" cellspacing="0"'
                + ' style="background:#FFF5F5;border:1.5px solid #F5C6CB;'
                + 'border-radius:10px;margin-bottom:20px;">'
                + '<tr><td style="padding:16px 20px 8px;">'
                + '<h3 style="color:#E24B4A;margin:0 0 12px;font-size:14px;">'
                + '🔴 Out of Stock (' + outOfStock.size() + ' product'
                + (outOfStock.size() > 1 ? 's' : '') + ')</h3>'
                + '</td></tr>'
                + '<tr><td style="padding:0 12px 12px;">'
                + '<table width="100%" cellpadding="0" cellspacing="0">'
                + outOfStockRows
                + '</table></td></tr></table>';
        }
        
        String lowStockSection = '';
        if (!lowStock.isEmpty()) {
            lowStockSection = '<table width="100%" cellpadding="0" cellspacing="0"'
                + ' style="background:#FFF8F5;border:1.5px solid #FFE4D4;'
                + 'border-radius:10px;margin-bottom:20px;">'
                + '<tr><td style="padding:16px 20px 8px;">'
                + '<h3 style="color:#FF6B1A;margin:0 0 12px;font-size:14px;">'
                + '⚠️ Low Stock (' + lowStock.size() + ' product'
                + (lowStock.size() > 1 ? 's' : '') + ')</h3>'
                + '</td></tr>'
                + '<tr><td style="padding:0 12px 12px;">'
                + '<table width="100%" cellpadding="0" cellspacing="0">'
                + lowStockRows
                + '</table></td></tr></table>';
        }
        
        String htmlBody =
            '<html><body style="margin:0;padding:0;background:#f4f4f4;font-family:Arial,sans-serif;">'
            + '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:30px 0;">'
            + '<tr><td align="center">'
            + '<table width="600" cellpadding="0" cellspacing="0"'
            + ' style="background:#fff;border-radius:12px;overflow:hidden;'
            + 'box-shadow:0 2px 8px rgba(0,0,0,0.08);">'
            
        // Header
        + '<tr><td style="background:#0A1628;padding:32px;text-align:center;">'
            + '<h1 style="color:#FF6B1A;margin:0;font-size:26px;letter-spacing:1px;">TalFlow Express</h1>'
            + '<p style="color:#fff;margin:8px 0 0;font-size:14px;">Stock Management Alert System</p>'
            + '</td></tr>'
            
        // Red Banner
        + '<tr><td style="background:#E24B4A;padding:16px;text-align:center;">'
            + '<p style="color:#fff;margin:0;font-size:16px;font-weight:bold;">'
            + '🔴 Stock Alert — Immediate Action Required</p>'
            + '</td></tr>'
            
        // Body
        + '<tr><td style="padding:36px 40px;">'
            + '<p style="color:#0A1628;font-size:16px;margin:0 0 8px;">Hi <strong>Sales Manager</strong>,</p>'
            + '<p style="color:#495057;font-size:14px;line-height:1.7;margin:0 0 24px;">'
            + 'This is an automated stock alert from TalFlow Express. '
            + 'The following products require your immediate attention.</p>'
            
        // Dynamic sections
        + outOfStockSection
            + lowStockSection
            
        // Actions box
        + '<table width="100%" cellpadding="0" cellspacing="0"'
            + ' style="background:#F0F8FF;border:1.5px solid #B8D4F0;border-radius:10px;margin-bottom:28px;">'
            + '<tr><td style="padding:16px 20px;">'
            + '<p style="color:#0A1628;margin:0 0 10px;font-size:13px;font-weight:bold;">📋 Recommended Actions</p>'
            + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Log in to Salesforce and update stock quantities</p>'
            + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Contact your supplier to reorder affected products</p>'
            + '<p style="color:#495057;font-size:13px;margin:4px 0;">✅ Update product availability status if needed</p>'
            + '</td></tr></table>'
            
        // CTA
        + '<table width="100%" cellpadding="0" cellspacing="0">'
            + '<tr><td align="center" style="padding-bottom:10px;">'
            + '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.salesforce.com"'
            + ' style="display:inline-block;background:#E24B4A;color:#fff;'
            + 'padding:14px 36px;border-radius:10px;text-decoration:none;'
            + 'font-size:13px;font-weight:bold;">View Products in Salesforce →</a>'
            + '</td></tr>'
            + '<tr><td align="center">'
            + '<a href="https://orgfarm-3f2e05ed36-dev-ed.develop.my.site.com/TalFlowExpress/s/"'
            + ' style="display:inline-block;background:#0A1628;color:#fff;'
            + 'padding:14px 36px;border-radius:10px;text-decoration:none;'
            + 'font-size:13px;font-weight:bold;margin-top:10px;">View TalFlow Express →</a>'
            + '</td></tr></table>'
            
        + '</td></tr>'
            
        // Footer
        + '<tr><td style="background:#0A1628;padding:24px 40px;text-align:center;">'
            + '<p style="color:#FF6B1A;font-size:13px;font-weight:bold;margin:0 0 6px;">TalFlow Express</p>'
            + '<p style="color:#495057;font-size:11px;margin:0;">© 2026 All rights reserved — Automated Stock Alert</p>'
            + '</td></tr>'
            
        + '</table></td></tr></table>'
            + '</body></html>';
        
        // ── Récupérer email destinataire ──────────────────────────
        List<Site_Configuration__mdt> configs = [
        SELECT Stock_Alert_Email__c FROM Site_Configuration__mdt
        WHERE DeveloperName = 'Stock_Alert_Email' LIMIT 1
    ];
        if (configs.isEmpty() || String.isBlank(configs[0].Stock_Alert_Email__c)) {
            System.debug('Stock alert: Stock_Alert_Email non configuré');
            return;
        }
        
        List<String> recipients = new List<String>{ configs[0].Stock_Alert_Email__c };
        
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        List<OrgWideEmailAddress> owea = [
        SELECT Id FROM OrgWideEmailAddress
        WHERE DisplayName = 'Hasnaoui Yassine' LIMIT 1
    ];
        if (!owea.isEmpty()) {
            mail.setOrgWideEmailAddressId(owea[0].Id);
        }
        
        mail.setToAddresses(recipients);
        mail.setSubject('🔴 TalFlow Express - Stock Alert');
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(plainBody);
        mail.setSaveAsActivity(false);
        
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Stock alert failed: ' + e.getMessage());
        }
    }
    public class StockInfo {
        @AuraEnabled public String productId;
        @AuraEnabled public Integer stockQuantity;
        @AuraEnabled public String availability;
        @AuraEnabled public Boolean canAddToCart;
    }
}